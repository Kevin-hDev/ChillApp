# P4 - Construction des Attaques (Rapport de travail)

## Statistiques

- **18 scenarios d'attaque** construits (ATK-001 a ATK-018)
- **1 faille non exploitable** (VULN-019 — post-quantique)
- **Couverture** : 19/19 vulns comptabilisees (18 + 1 = 19 = P3.total)

## Distribution

| Severite | Nombre | IDs |
|----------|--------|-----|
| CRITIQUE | 3 | ATK-001, ATK-002, ATK-003 |
| HAUTE | 7 | ATK-004 a ATK-010 |
| MOYENNE | 5 | ATK-011 a ATK-015 |
| BASSE | 3 | ATK-016, ATK-017, ATK-018 |

## Profils d'attaquants utilises

| Profil | Nombre de scenarios |
|--------|-------------------|
| Script kiddie | 6 |
| Competent | 10 |
| Expert | 2 |

## Validation

- Chaque VULN de P3 comptabilisee : OK
- Conservation comptages (18 + 1 = 19) : OK
- Chaque ATK a un profil d'attaquant : OK
- Chaque ATK a des etapes avec commandes : OK
- Chaque ATK a une evidence dans le code : OK
- Chaque ATK a severite + CVSS : OK
- VULN-019 non exploitable justifie : OK
