import 'model_parsers.dart';

class CameraFeed {
  const CameraFeed({
    required this.id,
    required this.title,
    required this.location,
    required this.isOnline,
    required this.viewers,
    required this.lastUpdated,
    this.alert,
  });

  final String id;
  final String title;
  final String location;
  final bool isOnline;
  final int viewers;
  final DateTime lastUpdated;
  final String? alert;

  factory CameraFeed.fromJson(Map<String, dynamic> json) {
    return CameraFeed(
      id: readString(json['id']),
      title: readString(json['title']),
      location: readString(json['location']),
      isOnline: readBool(json['isOnline']),
      viewers: readInt(json['viewers']),
      lastUpdated: readDateTime(json['lastUpdated']),
      alert: json['alert'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'location': location,
      'isOnline': isOnline,
      'viewers': viewers,
      'lastUpdated': lastUpdated,
      'alert': alert,
    };
  }
}
