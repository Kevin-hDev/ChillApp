package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"syscall"
	"time"

	"tailscale.com/client/tailscale"
	"tailscale.com/tsnet"
)

// Command represents a JSON command received on stdin.
type Command struct {
	Cmd string `json:"cmd"`
}

// PeerInfo represents a Tailscale peer.
type PeerInfo struct {
	Hostname string `json:"hostname"`
	IP       string `json:"ip"`
	OS       string `json:"os"`
	Online   bool   `json:"online"`
}

// Event represents a JSON event sent on stdout.
type Event struct {
	EventType    string     `json:"event"`
	State        string     `json:"state,omitempty"`
	URL          string     `json:"url,omitempty"`
	SelfHostname string     `json:"self_hostname,omitempty"`
	SelfIP       string     `json:"self_ip,omitempty"`
	Peers        []PeerInfo `json:"peers,omitempty"`
	Message      string     `json:"message,omitempty"`
}

var (
	srv         *tsnet.Server
	lc          *tailscale.LocalClient
	mu          sync.Mutex
	outMu       sync.Mutex
	fwdListener net.Listener
	fwdMu       sync.Mutex
)

func sendEvent(evt Event) {
	outMu.Lock()
	defer outMu.Unlock()
	data, _ := json.Marshal(evt)
	fmt.Fprintln(os.Stdout, string(data))
}

func getStateDir() string {
	switch runtime.GOOS {
	case "linux":
		home, _ := os.UserHomeDir()
		dir := filepath.Join(home, ".local", "share", "chill-app", "tailscale")
		os.MkdirAll(dir, 0700)
		return dir
	case "windows":
		dir := filepath.Join(os.Getenv("LOCALAPPDATA"), "chill-app", "tailscale")
		os.MkdirAll(dir, 0700)
		return dir
	case "darwin":
		home, _ := os.UserHomeDir()
		dir := filepath.Join(home, "Library", "Application Support", "chill-app", "tailscale")
		os.MkdirAll(dir, 0700)
		return dir
	default:
		dir := filepath.Join(os.TempDir(), "chill-app-tailscale")
		os.MkdirAll(dir, 0700)
		return dir
	}
}

func getHostname() string {
	h, err := os.Hostname()
	if err != nil {
		return "chill-app"
	}
	return h
}

func buildStatusEvent(eventName string) Event {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	status, err := lc.Status(ctx)
	if err != nil {
		return Event{EventType: "error", Message: err.Error()}
	}

	evt := Event{
		EventType: eventName,
		State:     status.BackendState,
	}

	if status.Self != nil {
		evt.SelfHostname = status.Self.HostName
		for _, ip := range status.Self.TailscaleIPs {
			if ip.Is4() {
				evt.SelfIP = ip.String()
				break
			}
		}
	}

	var peers []PeerInfo
	for _, peer := range status.Peer {
		p := PeerInfo{
			Hostname: peer.HostName,
			OS:       peer.OS,
			Online:   peer.Online,
		}
		for _, ip := range peer.TailscaleIPs {
			if ip.Is4() {
				p.IP = ip.String()
				break
			}
		}
		peers = append(peers, p)
	}
	sort.Slice(peers, func(i, j int) bool {
		if peers[i].Online != peers[j].Online {
			return peers[i].Online
		}
		return peers[i].Hostname < peers[j].Hostname
	})
	evt.Peers = peers

	return evt
}

// startForwarding écoute le port 22 sur le réseau Tailscale
// et redirige chaque connexion vers localhost:22 (serveur SSH local).
func startForwarding() {
	fwdMu.Lock()
	defer fwdMu.Unlock()

	if fwdListener != nil {
		return // déjà actif
	}
	if srv == nil {
		return
	}

	ln, err := srv.Listen("tcp", ":22")
	if err != nil {
		log.Printf("Échec démarrage forwarding SSH: %v", err)
		return
	}

	fwdListener = ln
	log.Println("SSH forwarding actif: Tailscale:22 → localhost:22")

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				log.Printf("Forwarding listener fermé: %v", err)
				return
			}
			go forwardConnection(conn)
		}
	}()
}

// forwardConnection relie une connexion Tailscale entrante à localhost:22.
func forwardConnection(tsConn net.Conn) {
	defer tsConn.Close()

	localConn, err := net.DialTimeout("tcp", "127.0.0.1:22", 5*time.Second)
	if err != nil {
		log.Printf("Connexion SSH locale échouée: %v", err)
		return
	}
	defer localConn.Close()

	done := make(chan struct{}, 2)
	go func() {
		io.Copy(localConn, tsConn)
		done <- struct{}{}
	}()
	go func() {
		io.Copy(tsConn, localConn)
		done <- struct{}{}
	}()

	<-done
}

// stopForwarding arrête l'écoute sur le port 22 Tailscale.
func stopForwarding() {
	fwdMu.Lock()
	defer fwdMu.Unlock()

	if fwdListener != nil {
		fwdListener.Close()
		fwdListener = nil
		log.Println("SSH forwarding arrêté")
	}
}

func main() {
	log.SetOutput(os.Stderr)

	// Gérer SIGTERM/SIGINT pour un arrêt propre
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigCh
		log.Println("Signal reçu, arrêt propre...")
		handleShutdown()
	}()

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), 64*1024)

	for scanner.Scan() {
		line := scanner.Text()
		var cmd Command
		if err := json.Unmarshal([]byte(line), &cmd); err != nil {
			sendEvent(Event{EventType: "error", Message: "Invalid JSON command"})
			continue
		}

		switch cmd.Cmd {
		case "start":
			handleStart()
		case "login":
			handleLogin()
		case "status":
			handleStatus()
		case "logout":
			handleLogout()
		case "shutdown":
			handleShutdown()
		default:
			sendEvent(Event{EventType: "error", Message: "Unknown command: " + cmd.Cmd})
		}
	}

	// stdin fermé (parent process mort) → arrêt propre
	handleShutdown()
}

func handleStart() {
	mu.Lock()
	defer mu.Unlock()

	if srv != nil {
		evt := buildStatusEvent("started")
		sendEvent(evt)
		return
	}

	srv = &tsnet.Server{
		Hostname:  getHostname(),
		Dir:       getStateDir(),
		Ephemeral: false,
		Logf: func(format string, args ...any) {
			log.Printf(format, args...)
		},
	}

	if err := srv.Start(); err != nil {
		sendEvent(Event{EventType: "error", Message: "Failed to start: " + err.Error()})
		srv = nil
		return
	}

	var err error
	lc, err = srv.LocalClient()
	if err != nil {
		sendEvent(Event{EventType: "error", Message: "Failed to get local client: " + err.Error()})
		srv.Close()
		srv = nil
		return
	}

	// Attendre que tsnet se reconnecte (jusqu'à 10s si état existant)
	for i := 0; i < 10; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		status, err := lc.Status(ctx)
		cancel()

		if err != nil {
			if i == 9 {
				sendEvent(Event{EventType: "error", Message: "Failed to get status: " + err.Error()})
				return
			}
			time.Sleep(1 * time.Second)
			continue
		}

		if status.BackendState == "Running" {
			evt := buildStatusEvent("started")
			sendEvent(evt)
			go startForwarding()
			return
		}

		if status.BackendState == "NeedsLogin" {
			sendEvent(Event{EventType: "started", State: status.BackendState})
			return
		}

		// État transitoire (Starting, etc.) → attendre
		log.Printf("BackendState: %s, attente...", status.BackendState)
		time.Sleep(1 * time.Second)
	}

	// Timeout — envoyer l'état actuel
	ctx2, cancel2 := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel2()
	status, err := lc.Status(ctx2)
	if err != nil {
		sendEvent(Event{EventType: "error", Message: "Timeout status: " + err.Error()})
	} else {
		sendEvent(Event{EventType: "started", State: status.BackendState})
	}
}

func handleLogin() {
	mu.Lock()
	if srv == nil || lc == nil {
		mu.Unlock()
		sendEvent(Event{EventType: "error", Message: "Server not started"})
		return
	}
	mu.Unlock()

	ctx := context.Background()

	if err := lc.StartLoginInteractive(ctx); err != nil {
		sendEvent(Event{EventType: "error", Message: "Login failed: " + err.Error()})
		return
	}

	go func() {
		authURLSent := false
		for i := 0; i < 90; i++ {
			time.Sleep(2 * time.Second)

			ctx2, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			status, err := lc.Status(ctx2)
			cancel()

			if err != nil {
				continue
			}

			if !authURLSent && status.AuthURL != "" {
				sendEvent(Event{EventType: "auth_url", URL: status.AuthURL})
				authURLSent = true
			}

			if status.BackendState == "Running" {
				evt := buildStatusEvent("connected")
				sendEvent(evt)
				go startForwarding()
				return
			}
		}
		sendEvent(Event{EventType: "error", Message: "Login timeout (3 minutes)"})
	}()
}

func handleStatus() {
	mu.Lock()
	defer mu.Unlock()

	if srv == nil || lc == nil {
		sendEvent(Event{EventType: "status", State: "NotStarted"})
		return
	}

	evt := buildStatusEvent("status")
	sendEvent(evt)
}

func handleLogout() {
	mu.Lock()
	defer mu.Unlock()

	if srv == nil || lc == nil {
		sendEvent(Event{EventType: "error", Message: "Server not started"})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	stopForwarding()

	if err := lc.Logout(ctx); err != nil {
		sendEvent(Event{EventType: "error", Message: "Logout failed: " + err.Error()})
		return
	}
	sendEvent(Event{EventType: "logged_out"})
}

func handleShutdown() {
	stopForwarding()

	mu.Lock()
	defer mu.Unlock()

	if srv != nil {
		srv.Close()
	}
	os.Exit(0)
}
