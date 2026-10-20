/// FuelPay shared core: models, state machine, Bluetooth protocol,
/// validators and design system used by both the customer and pump apps.
library fuelpay_core;

export 'src/models/fuel_type.dart';
export 'src/models/fuel_transaction.dart';
export 'src/models/transaction_status.dart';
export 'src/state/transaction_state_machine.dart';
export 'src/validation/amount_validator.dart';
export 'src/validation/transaction_id.dart';
export 'src/protocol/ble_constants.dart';
export 'src/protocol/protocol_message.dart';
export 'src/protocol/framing.dart';
export 'src/protocol/deduplicator.dart';
export 'src/theme/fuelpay_colors.dart';
export 'src/theme/fuelpay_theme.dart';
export 'src/widgets/common_widgets.dart';
export 'src/backend/api_client.dart';
export 'src/backend/local_store.dart';
export 'src/backend/local_demo_payment.dart';
