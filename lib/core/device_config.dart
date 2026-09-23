class DeviceConfig {
  final String displayName;
  final int vendorId;
  final int productId;

  const DeviceConfig({
    required this.displayName,
    required this.vendorId,
    required this.productId,
  });
}

/// Endoscopio del cliente. Cambia displayName por el nombre comercial real.
const kEndoscope = DeviceConfig(
  displayName: 'Endoscopio XXX',
  vendorId: 1878,
  productId: 1319,
);