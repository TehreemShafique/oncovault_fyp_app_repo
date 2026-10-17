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
    if (role.toLowerCase() == 'doctor') {
      final docData = Map<String, dynamic>.from(data);
      docData['availableDays'] = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
      docData['availableSlots'] = const [
        '08:00 AM', '09:30 AM', '11:00 AM',
        '01:30 PM', '03:00 PM', '04:30 PM',
      ];
      docData['isAvailable'] = true;
      await _db.collection('doctors').doc(uid).set(docData);
    } else {
      await _db.collection(_collectionForRole(role)).doc(uid).set(data);
    }
    await _db.collection('medical_id_directory').doc(medId.toUpperCase()).set({
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
      email = input.toLowerCase();
    } else {
      final lookupId = input.toUpperCase();
      final lookupDoc = await _db.collection('medical_id_directory').doc(lookupId).get();
      if (lookupDoc.exists && lookupDoc.data()?['email'] != null) {
        email = (lookupDoc.data()!['email'] as String).trim().toLowerCase();
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

    final cred = await _auth.signInWithEmailAndPassword(
      email: email, password: password,
    );

    // Attempt to load profile from /users
    DocumentSnapshot<Map<String, dynamic>> userDoc =
        await _db.collection('users').doc(cred.user!.uid).get();

    OVUser user;
    if (userDoc.exists && userDoc.data() != null) {
      user = OVUser.fromMap(userDoc.data()!);
    } else {
      // Self-healing fallback for legacy accounts where /users document was not created
      // Check role-specific collections (doctors, nurses, patients)
      Map<String, dynamic>? legacyData;
      String inferredRole = 'patient';

      final docSnap = await _db.collection('doctors').doc(cred.user!.uid).get();
      if (docSnap.exists && docSnap.data() != null) {
        legacyData = docSnap.data()!;
        inferredRole = 'doctor';
      } else {
        final nurseSnap = await _db.collection('nurses').doc(cred.user!.uid).get();
        if (nurseSnap.exists && nurseSnap.data() != null) {
          legacyData = nurseSnap.data()!;
          inferredRole = 'nurse';
        } else {
          final patientSnap = await _db.collection('patients').doc(cred.user!.uid).get();
          if (patientSnap.exists && patientSnap.data() != null) {
            legacyData = patientSnap.data()!;
            inferredRole = 'patient';
          }
        }
      }

      final uid = cred.user!.uid;
      final fallbackMedId = legacyData?['medicalId'] ??
          'OV-${inferredRole.toUpperCase().substring(0, 2)}-${uid.substring(0, 6).toUpperCase()}';
      final fallbackName = legacyData?['name'] ?? cred.user!.displayName ?? 'User';

      user = OVUser(
        uid: uid,
        name: fallbackName,
        email: cred.user!.email ?? email,
        medicalId: fallbackMedId,
        role: inferredRole,
        createdAt: DateTime.now(),
      );

      // Backfill to /users if allowed (e.g. patient self-registration rule)
      try {
        await _db.collection('users').doc(uid).set(user.toMap(), SetOptions(merge: true));
      } catch (_) {}
    }

    // Ensure medical_id_directory record exists for future Medical ID logins (Self-migration)
    if (user.medicalId.isNotEmpty) {
      try {
        final dirRef = _db.collection('medical_id_directory').doc(user.medicalId.toUpperCase());
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
    if (doc.exists && doc.data() != null) {
      return OVUser.fromMap(doc.data()!);
    }
    // Fallback for clinicians or patients if /users was not yet backfilled
    final docSnap = await _db.collection('doctors').doc(uid).get();
    if (docSnap.exists && docSnap.data() != null) {
      final d = docSnap.data()!;
      return OVUser(
        uid: uid,
        name: d['name'] ?? '',
        email: d['email'] ?? '',
        medicalId: d['medicalId'] ?? '',
        role: 'doctor',
        createdAt: DateTime.now(),
      );
    }
    final patientSnap = await _db.collection('patients').doc(uid).get();
    if (patientSnap.exists && patientSnap.data() != null) {
      final d = patientSnap.data()!;
      return OVUser(
        uid: uid,
        name: d['name'] ?? '',
        email: d['email'] ?? '',
        medicalId: d['medicalId'] ?? '',
        role: 'patient',
        createdAt: DateTime.now(),
      );
    }
    return null;
  }

  Future<void> signOut() async {
    try {
      await NotificationService().deleteCurrentDeviceToken();
    } catch (_) {}
    await _auth.signOut();
  }
}