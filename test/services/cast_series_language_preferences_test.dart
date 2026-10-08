// AUTHORED / NOT RUN: profile-scoped production storage, no receiver track IDs.
import 'package:debrify/services/cast_player_authority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.initializeLegacy();
  });
  test('series OFF and another series language survive independent storage reads', () async {
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttA',
        audioLanguage: 'en', subtitlesDisabled: true), permitted: () => true);
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttB',
        audioLanguage: 'ja', subtitleLanguage: 'es'), permitted: () => true);
    final a = await StorageService.getSeriesCastLanguagePreferences('ttA');
    final b = await StorageService.getSeriesCastLanguagePreferences('ttB');
    expect(a!.seriesIdentity, 'ttA');
    expect(a.subtitlesDisabled, isTrue);
    expect(a.audioLanguage, 'en');
    expect(b!.seriesIdentity, 'ttB');
    expect(b.subtitleLanguage, 'es');
    expect(b.subtitlesDisabled, isFalse);
    expect(await StorageService.getSeriesCastLanguagePreferences('ttC'), isNull);
  });
  test('audio-only series choice preserves durable subtitle OFF', () async {
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttA',
        audioLanguage: 'en', subtitlesDisabled: true), permitted: () => true);
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttA',
        audioLanguage: 'fr', updateSubtitle: false), permitted: () => true);
    final current = await StorageService.getSeriesCastLanguagePreferences('ttA');
    expect(current!.audioLanguage, 'fr');
    expect(current.subtitlesDisabled, isTrue);
  });

  test('obsolete scoped preference cannot overwrite the current series intent', () async {
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttB',
        subtitleLanguage: 'es'), permitted: () => true);
    await StorageService.saveSeriesCastLanguagePreferences(
      const CastPlayerSeriesLanguagePreference(seriesIdentity: 'ttB',
        subtitlesDisabled: true), permitted: () => false);
    final current = await StorageService.getSeriesCastLanguagePreferences('ttB');
    expect(current!.subtitleLanguage, 'es');
    expect(current.subtitlesDisabled, isFalse);
  });
}
