import 'base_intent.dart';

class ClarifyIntent extends BaseIntent {
  final String message;
  final String? missingFor;

  const ClarifyIntent({required this.message, this.missingFor}) : super('clarify');

  factory ClarifyIntent.fromMap(Map<String, dynamic> map) => ClarifyIntent(
    message: map['message'] as String,
    missingFor: map['missing_for'] as String?,
  );
}
