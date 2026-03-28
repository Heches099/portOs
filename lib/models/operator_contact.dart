class OperatorContact {
  const OperatorContact({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    required this.phoneNumber,
    required this.whatsAppNumber,
    required this.telegramHandle,
    required this.notes,
  });

  final String id;
  final String name;
  final String role;
  final String email;
  final String phoneNumber;
  final String whatsAppNumber;
  final String telegramHandle;
  final String notes;

  factory OperatorContact.fromJson(Map<String, dynamic> json) {
    return OperatorContact(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      whatsAppNumber: json['whatsAppNumber'] as String? ?? '',
      telegramHandle: json['telegramHandle'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'email': email,
      'phoneNumber': phoneNumber,
      'whatsAppNumber': whatsAppNumber,
      'telegramHandle': telegramHandle,
      'notes': notes,
    };
  }
}
