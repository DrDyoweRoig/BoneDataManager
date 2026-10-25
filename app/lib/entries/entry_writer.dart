import 'entry.dart';

/// Where the UI sends new, changed and deleted entries: the local file directly, or the sync
/// engine for cloud databases.
abstract class EntryWriter {
  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer);
  Future<Entry> updateEntry(String id, EntryDraft data, String observer);
  Future<void> deleteEntry(String id, String observer);
}
