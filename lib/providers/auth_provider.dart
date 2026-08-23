import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'dart:async';

final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  if (Firebase.apps.isNotEmpty) {
    return FirebaseAuth.instance;
  }
  return null;
});

final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  if (Firebase.apps.isNotEmpty) {
    return FirebaseFirestore.instance;
  }
  return null;
});

// Stream of Firebase Auth State
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) {
    // Return a logged-in Mock User for testing on Web
    return Stream.value(MockUser(uid: 'mock_uid_123', email: 'mock@example.com'));
  }
  return auth.authStateChanges();
});

// Local session store for Mock Mode — populated on registration/login
final localSessionProvider = StateProvider<UserModel?>((ref) => null);

// Provides current UserModel from Firestore, falls back to local session in Mock Mode or if doc is missing
final currentUserProvider = StreamProvider<UserModel?>((ref) async* {
  final firestore = ref.watch(firestoreProvider);
  final authUser = ref.watch(authStateProvider).value;

  // In Mock Mode (no Firebase), return local session
  if (firestore == null) {
    yield ref.watch(localSessionProvider);
    return;
  }

  // If we have no Firebase user, return null
  if (authUser == null) {
    yield null;
    return;
  }

  // Yield existing local session initially if present to prevent UI flickering
  final initialLocalUser = ref.read(localSessionProvider);
  if (initialLocalUser != null) {
    yield initialLocalUser;
  }

  try {
    await for (final doc in firestore.collection('users').doc(authUser.uid).snapshots()) {
      if (doc.exists && doc.data() != null) {
        final userModel = UserModel.fromMap(doc.data()!, doc.id);
        yield userModel;
      } else {
        // Document missing in Firestore but user is logged in via Auth.
        // Create a fallback user model
        final fallbackUser = UserModel(
          uid: authUser.uid,
          email: authUser.email ?? '',
          role: 'passenger', // default to passenger role
          name: authUser.displayName ?? (authUser.email != null ? authUser.email!.split('@').first : 'User'),
          phone: authUser.phoneNumber ?? '',
          createdAt: DateTime.now(),
        );
        
        // Write it to Firestore asynchronously so it exists next time
        firestore.collection('users').doc(authUser.uid).set(fallbackUser.toMap()).catchError((e) {
          debugPrint('Failed to create missing user document: $e');
        });
        
        yield fallbackUser;
      }
    }
  } catch (error) {
    debugPrint('Firestore snapshot error caught: $error');
    yield ref.read(localSessionProvider);
  }
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;

  AuthController(this._auth, this._firestore) : super(const AsyncValue.data(null));

  Future<void> loginWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    if (_auth == null) {
      state = const AsyncValue.data(null);
      return; 
    }
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    if (_auth == null) {
      state = const AsyncValue.data(null);
      return MockUserCredential(MockUser(uid: 'mock_uid_123', email: email));
    }
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      state = const AsyncValue.data(null);
      return cred;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> createUserDocument(UserModel user) async {
    state = const AsyncValue.loading();
    if (_firestore == null) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      await _firestore.collection('users').doc(user.uid).set(user.toMap());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<UserModel?> getUserDocument(String uid) async {
    if (_firestore == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data()!, doc.id);
      }
    } catch (e) {
      // Handle silently for auth flow checks
    }
    return null;
  }

  Future<UserCredential?> signInWithGoogle() async {
    state = const AsyncValue.loading();
    if (_auth == null) {
      // Mock Google sign-in
      state = const AsyncValue.data(null);
      return MockUserCredential(MockUser(uid: 'google_mock_uid', email: 'google@example.com', displayName: 'Google User'));
    }
    try {
      final googleUser = await GoogleSignIn(
        clientId: kIsWeb ? '252031920183-qb88a1c6sagbrhtij9scukijh6nqre6j.apps.googleusercontent.com' : null,
        serverClientId: '252031920183-qb88a1c6sagbrhtij9scukijh6nqre6j.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) {
        state = const AsyncValue.data(null);
        return null; // User cancelled
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      state = const AsyncValue.data(null);
      return result;
    } catch (e, st) {
      final msg = e.toString();
      if (msg.contains('SERVICE_DISABLED') || msg.contains('People API')) {
        state = AsyncValue.error(
          'Google People API is not enabled. Please enable it in Google Cloud Console and try again.',
          st,
        );
      } else {
        state = AsyncValue.error(e, st);
      }
      return null;
    }
  }

  Future<void> signOut() async {
    if (_auth != null) {
      await GoogleSignIn(
        clientId: '252031920183-qb88a1c6sagbrhtij9scukijh6nqre6j.apps.googleusercontent.com',
      ).signOut();
      await _auth.signOut();
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  
  return AuthController(auth, firestore);
});

// --- MOCK CLASSES FOR WEB TESTING ---

class MockUser implements User {
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;

  MockUser({required this.uid, this.email, this.displayName});

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #uid) return uid;
    if (invocation.memberName == #email) return email;
    return super.noSuchMethod(invocation);
  }
}

class MockUserCredential implements UserCredential {
  @override
  final User? user;
  MockUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #user) return user;
    return super.noSuchMethod(invocation);
  }
}
