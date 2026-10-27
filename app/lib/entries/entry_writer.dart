import 'entry.dart';

/// Where the UI sends new, changed and deleted entries: the local file directly, or the sync
/// engine for cloud databases.
abstract class EntryWriter {
  /// [ids]: chosen once per form, so pressing Save again after a lost answer can't duplicate entries.
  /// [sharedId]: all drafts get one Ref ID (teeth of one specimen).
  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer,
      {List<String>? ids, bool sharedId = false});

  /// New rows under an existing Ref ID.
  Future<List<Entry>> addToGroup(String refId, int number, List<EntryDraft> drafts, String observer,
      {List<String>? ids});
  Future<Entry> updateEntry(String id, EntryDraft data, String observer);
  Future<void> deleteEntry(String id, String observer);
}
