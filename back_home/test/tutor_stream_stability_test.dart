// SDK references are substituted only at the test boundary.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Firestore implements FirebaseFirestore {
  final streams =
      <String, StreamController<QuerySnapshot<Map<String, dynamic>>>>{};
  final listens = <String, int>{};

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String path) => streams
      .putIfAbsent(
        path,
        () => StreamController.broadcast(
          onListen: () => listens[path] = (listens[path] ?? 0) + 1,
        ),
      )
      .stream;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Firestore store;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Document(store, '$path/$id');
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #orderBy) return this;
    if (invocation.memberName == #snapshots) return store.watch(path);
    return super.noSuchMethod(invocation);
  }
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Firestore store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueryDocument implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Functions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final messages in [false, true]) {
    testWidgets(
      '${messages ? 'Tutor messages' : 'Tutor history'} stay visible on rebuild',
      (tester) async {
        final store = _Firestore();
        final repository = AiChatRepository(
          uid: 'me',
          firestore: store,
          functions: _Functions(),
          storage: _Storage(),
        );
        final revision = ValueNotifier(0);
        addTearDown(revision.dispose);
        addTearDown(() async {
          for (final stream in store.streams.values) {
            await stream.close();
          }
        });
        final path = messages
            ? 'users/me/tutorSessions/session/messages'
            : 'users/me/tutorSessions';
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (context, value, _) => StreamBuilder<List<Object>>(
                stream: messages
                    ? repository.watchTutorMessages('session')
                    : repository.watchTutorSessions(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading');
                  }
                  final item = snapshot.data!.first;
                  return Text(
                    item is TutorSession
                        ? item.title
                        : (item as AiMessage).text,
                  );
                },
              ),
            ),
          ),
        );
        store.streams[path]!.add(
          _Snapshot([
            _QueryDocument(
              'session',
              messages
                  ? {'role': 'assistant', 'text': 'Tutor answer'}
                  : {'title': 'Saved question', 'subtitle': 'Earlier question'},
            ),
          ]),
        );
        await tester.pump();
        final label = messages ? 'Tutor answer' : 'Saved question';
        expect(find.text(label), findsOneWidget);

        // Rebuild as menu visibility, history search, or selected-session state
        // changes. No new network event is needed to keep the content visible.
        for (var i = 0; i < 4; i++) {
          revision.value++;
          await tester.pump();
          expect(find.text('Loading'), findsNothing);
          expect(find.text(label), findsOneWidget);
        }
        expect(store.listens[path], 1);
        if (messages) {
          expect(
            repository.watchTutorMessages('another-session'),
            isNot(same(repository.watchTutorMessages('session'))),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
