import 'base_intent.dart';

class CompleteIntent extends BaseIntent {
  final String searchTerm;
  final String scope; // 'today' | 'all'

  const CompleteIntent({required this.searchTerm, required this.scope}) : super('complete');

  factory CompleteIntent.fromMap(Map<String, dynamic> map) => CompleteIntent(
    searchTerm: map['search_term'] as String,
    scope: map['scope'] as String? ?? 'all',
  );
}
