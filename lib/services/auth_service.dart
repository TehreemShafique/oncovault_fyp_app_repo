import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

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
    await cred.user!.updateDisplayName(name.trim());
    return user;
  }

  Future<OVUser?> signIn({
    required String medicalId,
    required String password,
  }) async {
    final snap = await _db
        .collection('users')
        .where('medicalId', isEqualTo: medicalId.trim().toUpperCase())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No account found for Medical ID: $medicalId',
      );
    }
    final email = snap.docs.first.data()['email'] as String;
    final cred  = await _auth.signInWithEmailAndPassword(
      email: email, password: password,
    );
    final userDoc = await _db.collection('users').doc(cred.user!.uid).get();
    if (!userDoc.exists) return null;
    return OVUser.fromMap(userDoc.data()!);
  }

  Future<OVUser?> fetchProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return OVUser.fromMap(doc.data()!);
  }

  Future<void> signOut() => _auth.signOut();
}