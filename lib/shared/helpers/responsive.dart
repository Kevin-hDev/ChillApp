/// Helper pour le padding responsif utilise par tous les ecrans.
double responsivePadding(double width) => width < 600
    ? 16.0
    : width < 900
    ? 24.0
    : 32.0;
