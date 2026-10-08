import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  String _collectionForRole(String role) {
    switch (role.toLowerCase()) {
      case 'doctor': return 'doctors';
      case 'nurse':  return 'nurses';
      case 'admin':  return 'admins';
      default:       return 'patients';
    }
  }

  Future<OVUser?> signUp({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid    = cred.user!.uid;
    final prefix = role.toUpperCase().substring(0, 2);
    final medId  = 'OV-$prefix-${uid.substring(0, 6).toUpperCase()}';

    final user = OVUser(
      uid: uid, name: name.trim(), email: email.trim(),
      medicalId: medId, role: role, createdAt: DateTime.now(),
    );
    final data = user.toMap();

    await _db.collection('users').doc(uid).set(data);
    await _db.collection(_collectionForRole(role)).doc(uid).set(data);
    await _db.collection('medical_id_directory').doc(medId).set({
      'email': email.trim(),
      'uid': uid,
    });
    await cred.user!.updateDisplayName(name.trim());
    try {
      await NotificationService().registerCurrentDeviceToken();
    } catch (_) {}
    return user;
  }

  Future<OVUser?> signIn({
    required String medicalId,
    required String password,
  }) async {
    final input = medicalId.trim();
    String email;

    if (input.contains('@')) {
      // Direct Email login bypasses directory lookup completely
      email = input;
    } else {
      final lookupId = input.toUpperCase();
      final lookupDoc = await _db.collection('medical_id_directory').doc(lookupId).get();
      if (lookupDoc.exists && lookupDoc.data()?['email'] != null) {
        email = lookupDoc.data()!['email'] as String;
      } else {
        // Under Phase 1A security rules, unauthenticated queries on /users are strictly blocked.
        // Legacy accounts not yet indexed in medical_id_directory must authenticate via Email + Password,
        // which automatically self-migrates their Medical ID mapping upon successful login.
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Medical ID "$medicalId" not recognized. If this is an existing account, please sign in with your email address.',
        );
      }
    }

    final cred  = await _auth.signInWithEmailAndPassword(
      email: email, password: password,
    );
    final userDoc = await _db.collection('users').doc(cred.user!.uid).get();
    if (!userDoc.exists) return null;
    final user = OVUser.fromMap(userDoc.data()!);

    // Ensure medical_id_directory record exists for future Medical ID logins
    if (user.medicalId.isNotEmpty) {
      try {
        final dirRef = _db.collection('medical_id_directory').doc(user.medicalId);
        final dirDoc = await dirRef.get();
        if (!dirDoc.exists) {
          await dirRef.set({'email': user.email, 'uid': user.uid});
        }
      } catch (_) {}
    }

    try {
      await NotificationService().registerCurrentDeviceToken();
    } catch (_) {}

    return user;
  }

  Future<OVUser?> fetchProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return OVUser.fromMap(doc.data()!);
  }

  Future<void> signOut() async {
    try {
      await NotificationService().deleteCurrentDeviceToken();
    } catch (_) {}
    await _auth.signOut();
  }
}