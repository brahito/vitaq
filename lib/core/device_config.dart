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

/// Endoscopio del cliente.
const kEndoscope = DeviceConfig(
  displayName: 'Endoscopio',
  vendorId: 1878,
  productId: 1319,
);