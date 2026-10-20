/// Fuel types supported by the demonstration.
enum FuelType {
  petrol('PETROL'),
  diesel('DIESEL');

  const FuelType(this.wireName);

  /// Value used on the wire, in QR payloads and in the backend API.
  final String wireName;

  static FuelType fromWire(String? value) {
    switch (value?.toUpperCase()) {
      case 'PETROL':
        return FuelType.petrol;
      case 'DIESEL':
        return FuelType.diesel;
      default:
        throw ArgumentError('Unknown fuel type: $value');
    }
  }

  static bool isValid(String? value) =>
      value != null && ['PETROL', 'DIESEL'].contains(value.toUpperCase());

  /// Display label (keeps user-facing copy simple).
  String get label => this == FuelType.petrol ? 'Petrol' : 'Diesel';
}
