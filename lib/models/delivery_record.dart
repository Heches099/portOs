import 'model_parsers.dart';

class DeliveryRecord {
  DeliveryRecord({
    required this.containerId,
    required this.shipmentCode,
    required this.destination,
    required this.eta,
    required this.status,
    required this.priority,
    required this.itemsCount,
    required this.expectedGateOutAt,
    required this.verifiedAt,
    required this.exceptionReason,
  });

  final String containerId;
  final String shipmentCode;
  final String destination;
  final DateTime eta;
  final String status;
  final String priority;
  final int itemsCount;
  final DateTime expectedGateOutAt;
  final DateTime? verifiedAt;
  final String? exceptionReason;

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) {
    return DeliveryRecord(
      containerId: readString(json['containerId']),
      shipmentCode: readString(json['shipmentCode']),
      destination: readString(json['destination']),
      eta: readDateTime(json['eta']),
      status: readString(json['status']),
      priority: readString(json['priority']),
      itemsCount: readInt(json['itemsCount']),
      expectedGateOutAt: readDateTime(json['expectedGateOutAt']),
      verifiedAt:
          json['verifiedAt'] == null ? null : readDateTime(json['verifiedAt']),
      exceptionReason: json['exceptionReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'containerId': containerId,
      'shipmentCode': shipmentCode,
      'destination': destination,
      'eta': eta,
      'status': status,
      'priority': priority,
      'itemsCount': itemsCount,
      'expectedGateOutAt': expectedGateOutAt,
      'verifiedAt': verifiedAt,
      'exceptionReason': exceptionReason,
    };
  }
}
