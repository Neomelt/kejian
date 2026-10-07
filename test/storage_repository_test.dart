import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/data/storage_repository.dart';
import 'package:kejian/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('state and snapshots round-trip without destroying revisions', () async {
    final repository = StorageRepository(path: ':memory:');
    addTearDown(repository.close);

    expect(await repository.load(), ScheduleData.blank());
    final sample = ScheduleData.sample();
    await repository.save(sample);
    final snapshot = await repository.snapshot();
    await repository.save(ScheduleData.blank());

    expect((await repository.listSnapshots()).map((item) => item.id), [
      snapshot.id,
    ]);
    expect(await repository.restore(snapshot.id), sample);
    expect(await repository.load(), sample);
  });

  test('missing snapshots are rejected without changing state', () async {
    final repository = StorageRepository(path: ':memory:');
    addTearDown(repository.close);
    final sample = ScheduleData.sample();
    await repository.save(sample);

    await expectLater(
      repository.restore(404),
      throwsA(isA<StorageException>()),
    );
    expect(await repository.load(), sample);
  });
}
