import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';

void main() {
  test('Golden-branded local channel preserves independent cover', () {
    const cover = 'https://example.org/golden-channel-cover.svg';
    final channel = StremioTvChannel.local(
      catalogId: 'golden_channel',
      catalogName: 'Golden Channel',
      catalogType: 'movie',
      channelNumber: 607,
      coverUrl: cover,
      items: [
        StremioMeta.fromJson(const {
          'id': 'tt0111161',
          'type': 'movie',
          'name': 'The Shawshank Redemption',
          'poster': 'https://example.org/title-poster.jpg',
        }),
      ],
    );
    expect(channel.id, 'local:golden_channel:movie');
    expect(channel.displayName, 'Golden Channel');
    expect(channel.coverUrl, cover);
    expect(channel.items.single.poster, isNot(channel.coverUrl));
    expect(channel.isLocal, isTrue);
  });

  test('Unbranded local catalogs preserve legacy display name', () {
    final channel = StremioTvChannel.local(
      catalogId: 'old_catalog',
      catalogName: 'Old Catalog',
      catalogType: 'movie',
      channelNumber: 1,
      items: [],
    );
    expect(channel.coverUrl, isNull);
    expect(channel.displayName, 'Local: Old Catalog');
  });
}
