import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/doctor_model.dart';
import '../../services/consent_service.dart';
import '../../services/fabric_gateway_service.dart';
import '../../theme/app_theme.dart';

// Signup stores ISO dates; clinician profiles may use Firestore timestamps.
// Normalize only this picker, without changing shared doctor model behavior.
DoctorModel consentDoctorFromDocument(String id, Map<String, dynamic> data) {
  final normalized = Map<String, dynamic>.from(data);
  final rawDate = normalized['createdAt'];
  if (rawDate is String) {
    final date = DateTime.tryParse(rawDate);
    if (date == null) {
      throw const FormatException('Doctor profile creation date is invalid.');
    }
    normalized['createdAt'] = Timestamp.fromDate(date);
  } else if (rawDate is DateTime) {
    normalized['createdAt'] = Timestamp.fromDate(rawDate);
  } else if (rawDate is int) {
    normalized['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(rawDate);
  }
  normalized['uid'] = id;
  return DoctorModel.fromMap(normalized);
}

class PatientConsentScreen extends StatefulWidget {
  final String patientId;
  final ConsentService? consentService;
  final Stream<List<DoctorModel>>? doctorsStream;

  const PatientConsentScreen({
    super.key,
    required this.patientId,
    this.consentService,
    this.doctorsStream,
  });

  @override
  State<PatientConsentScreen> createState() => _PatientConsentScreenState();
}

enum _ConsentState {
  unselected,
  checking,
  pending,
  active,
  revoked,
  none,
  expired,
  unavailable
}

class _PatientConsentScreenState extends State<PatientConsentScreen> {
  DoctorModel? _selectedDoctor;
  _ConsentState _status = _ConsentState.unselected;
  bool _mutating = false;
  bool _confirming = false;
  bool _recovering = false;
  Timer? _recoveryTimer;
  int _recoveryChecks = 0;
  int _recoveryGeneration = 0;
  static const _maxRecoveryChecks = 3;
  final Map<String, bool> _projectionRetries = {};
  final Set<String> _pendingOutcomes = {};
  String? _error;
  Map<String, dynamic>? _proof;
  List<Map<String, dynamic>>? _history;
  bool _historyLoading = false;
  int _consentRequest = 0;
  late final _service = widget.consentService ?? ConsentService();
  StreamSubscription<List<DoctorModel>>? _doctorSubscription;
  Timer? _doctorTimer;
  int _doctorAttempt = 0;
  AsyncSnapshot<List<DoctorModel>> _doctorSnapshot =
      const AsyncSnapshot.waiting();

  @override
  void initState() {
    super.initState();
    _startDoctorLoading();
  }

  void _startDoctorLoading() {
    _cancelRecovery();
    final attempt = ++_doctorAttempt;
    _doctorSubscription?.cancel();
    _doctorTimer?.cancel();
    _doctorSnapshot = const AsyncSnapshot.waiting();
    _consentRequest++;
    _history = null;
    _historyLoading = false;
    _selectedDoctor = null;
    _status = _ConsentState.unselected;
    _proof = null;
    _error = null;
    void fail(Object error) {
      if (!mounted || attempt != _doctorAttempt) return;
      _doctorTimer?.cancel();
      final code = error is FirebaseException
          ? error.code
          : error is TimeoutException
              ? 'initial-snapshot-timeout'
              : error is FormatException || error is TypeError
                  ? 'profile-parsing'
                  : 'listener-error';
      _doctorDiagnostic(
          'failed attempt=$attempt code=$code type=${error.runtimeType}');
      setState(() => _doctorSnapshot =
          AsyncSnapshot.withError(ConnectionState.active, error));
    }

    _doctorTimer = Timer(const Duration(seconds: 15), () {
      fail(TimeoutException('The doctor list took too long to load.'));
    });
    try {
      final source = widget.doctorsStream ?? _registeredDoctors();
      _doctorDiagnostic('subscribed attempt=$attempt');
      _doctorSubscription = source.listen(
          (doctors) {
            if (!mounted || attempt != _doctorAttempt) return;
            _doctorTimer?.cancel();
            _doctorDiagnostic(
                'loaded attempt=$attempt count=${doctors.length}');
            setState(() => _doctorSnapshot =
                AsyncSnapshot.withData(ConnectionState.active, doctors));
          },
          onError: (Object error) => fail(error),
          onDone: () {
            if (!_doctorSnapshot.hasData && !_doctorSnapshot.hasError) {
              fail(StateError('The doctor list closed before returning data.'));
            }
          });
    } catch (error) {
      fail(error);
    }
  }

  void _doctorDiagnostic(String message) {
    if (kDebugMode) debugPrint('[ConsentDoctors] $message');
  }

  Stream<List<DoctorModel>> _registeredDoctors() {
    final firestore = FirebaseFirestore.instance;
    _doctorDiagnostic(
        'source=firestore signedIn=${FirebaseAuth.instance.currentUser != null}');
    return firestore.collection('doctors').snapshots().map((snapshot) {
      _doctorDiagnostic(
          'snapshot count=${snapshot.docs.length} fromCache=${snapshot.metadata.isFromCache}');
      try {
        return snapshot.docs
            .map((doc) => consentDoctorFromDocument(doc.id, doc.data()))
            .toList();
      } catch (error) {
        // Never log document contents, identifiers, exception messages or tokens.
        _doctorDiagnostic('parse_failed type=${error.runtimeType}');
        throw const FormatException(
            'A registered doctor profile could not be read.');
      }
    });
  }

  @override
  void dispose() {
    _cancelRecovery();
    _doctorAttempt++;
    _doctorTimer?.cancel();
    _doctorSubscription?.cancel();
    super.dispose();
  }

  bool get _busy => _mutating || _status == _ConsentState.checking;

  Future<void> _checkConsent(DoctorModel doctor) async {
    _cancelRecovery();
    final request = ++_consentRequest;
    setState(() {
      _selectedDoctor = doctor;
      _history = null;
      _historyLoading = false;
      _status = _ConsentState.checking;
      _error = null;
      _proof = null;
    });
    if (_pendingOutcomes.contains(doctor.uid)) {
      setState(() => _status = _ConsentState.pending);
      return;
    }
    try {
      final result = await _service
          .checkConsent(patientId: widget.patientId, doctorId: doctor.uid)
          .timeout(const Duration(seconds: 12));
      if (!mounted || request != _consentRequest) return;
      if (kDebugMode) {
        debugPrint(
            '[ConsentCheck] success status=${result['status']} active=${result['active']} proofPresent=${result['txId'] is String}');
      }
      setState(() => _applyResult(result, query: true));
      await _loadHistory(doctor.uid, request);
    } catch (error) {
      if (request == _consentRequest) _showError(error);
    }
  }

  Future<void> _loadHistory(String doctorId, int request) async {
    setState(() => _historyLoading = true);
    try {
      final history = await _service
          .getHistory(patientId: widget.patientId, doctorId: doctorId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || request != _consentRequest) return;
      setState(() => _history = history);
    } catch (error) {
      _consentDiagnostic(error, operation: 'history');
    } finally {
      if (mounted && request == _consentRequest) {
        setState(() => _historyLoading = false);
      }
    }
  }

  void _consentDiagnostic(Object error, {String operation = 'check'}) {
    if (!kDebugMode) return;
    if (error is FabricGatewayException) {
      debugPrint(
          '[ConsentCheck] operation=$operation http=${error.statusCode} code=${error.code}');
    } else {
      debugPrint(
          '[ConsentCheck] operation=$operation type=${error.runtimeType}');
    }
  }

  void _applyResult(Map<String, dynamic> result, {bool query = false}) {
    final status = result['status'];
    if (status == 'GRANTED' && (!query || result['active'] == true)) {
      _status = _ConsentState.active;
    } else if (status == 'REVOKED') {
      _status = _ConsentState.revoked;
    } else if (status == 'NOT_FOUND') {
      _status = _ConsentState.none;
    } else if (status == 'EXPIRED') {
      _status = _ConsentState.expired;
    } else {
      throw const FormatException(
          'The ledger returned an unrecognized consent state.');
    }
    _proof = Map<String, dynamic>.from(result);
  }

  Future<void> _changeAccess({required bool grant}) async {
    final doctor = _selectedDoctor;
    if (doctor == null || _busy || _confirming) return;
    if (_pendingOutcomes.contains(doctor.uid)) return;
    final projectionOnly = _projectionRetries[doctor.uid] == grant;
    _confirming = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
              projectionOnly
                  ? 'Sync confirmed access change?'
                  : grant
                      ? 'Grant doctor access?'
                      : 'Revoke doctor access?',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          content: Text(projectionOnly
              ? 'Consent is already confirmed on Hyperledger Fabric. This retries the application update for the same request.'
              : grant
                  ? 'Allow ${doctor.name} to access your records for direct clinical care? This requests a consent transaction through Hyperledger Fabric.'
                  : 'Revoke Direct Care access for ${doctor.name}? This requests a revocation transaction through Hyperledger Fabric.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                    backgroundColor: grant ? OV.primary : OV.error),
                child: Text(projectionOnly
                    ? 'Confirm sync'
                    : grant
                        ? 'Confirm grant'
                        : 'Confirm revocation')),
          ],
        ),
      );
    } finally {
      _confirming = false;
    }
    if (confirmed != true || !mounted) return;
    _cancelRecovery();
    setState(() {
      _mutating = true;
      _history = null;
      _historyLoading = false;
      _consentRequest++;
      _error = null;
      _proof = null;
    });
    try {
      final result = projectionOnly
          ? await _service.reconcileConsent(doctorId: doctor.uid)
          : grant
              ? await _service.grantConsent(doctorId: doctor.uid)
              : await _service.revokeConsent(doctorId: doctor.uid);
      if (!mounted) return;
      if (result['operationStatus'] == 'NONE') {
        _projectionRetries.remove(doctor.uid);
        _pendingOutcomes.remove(doctor.uid);
        await _checkConsent(doctor);
        return;
      }
      setState(() {
        _pendingOutcomes.remove(doctor.uid);
        _applyResult(result);
        if (result['projectionStatus'] == 'PENDING') {
          _projectionRetries[doctor.uid] = grant;
        } else {
          _projectionRetries.remove(doctor.uid);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['projectionStatus'] == 'PENDING'
            ? 'Consent confirmed on blockchain. The application access update is pending; retry the same request to synchronize it.'
            : 'Consent status: ${_displayConsentStatus(result['status'])}'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (error) {
      if (!mounted) return;
      if (error is! FabricGatewayException ||
          ![
            'FEATURE_DISABLED',
            'CONSENT_REJECTED',
            'UNAUTHENTICATED',
            'FORBIDDEN',
            'BAD_REQUEST'
          ].contains(error.code)) {
        _pendingOutcomes.add(doctor.uid);
      }
      _showError(error,
          operationPending: _pendingOutcomes.contains(doctor.uid));
      if (_pendingOutcomes.contains(doctor.uid)) _scheduleRecovery(doctor.uid);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryGeneration++;
    _recoveryChecks = 0;
  }

  void _scheduleRecovery(String doctorId) {
    if (!mounted || _selectedDoctor?.uid != doctorId) return;
    _recoveryTimer?.cancel();
    if (_recoveryChecks >= _maxRecoveryChecks) {
      setState(() => _error =
          'The request outcome is still unknown. Automatic checks have paused. Use Check request outcome later. Do not submit another access change.');
      return;
    }
    final generation = _recoveryGeneration;
    _recoveryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted &&
          generation == _recoveryGeneration &&
          _selectedDoctor?.uid == doctorId &&
          _pendingOutcomes.contains(doctorId)) {
        _recoverAccess(automatic: true);
      }
    });
  }

  Future<void> _recoverAccess({bool automatic = false}) async {
    final doctor = _selectedDoctor;
    if (doctor == null || _busy) return;
    if (!automatic) _cancelRecovery();
    final generation = _recoveryGeneration;
    _recoveryChecks++;
    setState(() {
      _mutating = true;
      _recovering = true;
      _status = _ConsentState.pending;
    });
    try {
      final result = await _service
          .reconcileConsent(doctorId: doctor.uid)
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _recoveryGeneration) return;
      if (result['operationStatus'] != 'NONE') {
        setState(() {
          _applyResult(result);
          _error = null;
          _pendingOutcomes.remove(doctor.uid);
          if (result['projectionStatus'] == 'PENDING') {
            _projectionRetries[doctor.uid] = result['status'] == 'GRANTED';
          } else {
            _projectionRetries.remove(doctor.uid);
          }
        });
        await _loadHistory(doctor.uid, _consentRequest);
      } else {
        _pendingOutcomes.remove(doctor.uid);
        _projectionRetries.remove(doctor.uid);
        await _checkConsent(doctor);
      }
    } catch (error) {
      if (!mounted || generation != _recoveryGeneration) return;
      final denied = error is FabricGatewayException &&
          [401, 403].contains(error.statusCode);
      final rejected =
          error is FabricGatewayException && error.code == 'CONSENT_REJECTED';
      if (rejected) {
        _pendingOutcomes.remove(doctor.uid);
      } else {
        _pendingOutcomes.add(doctor.uid);
      }
      _showError(error, operationPending: !rejected);
      if (!denied && !rejected) _scheduleRecovery(doctor.uid);
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
          _recovering = false;
        });
      }
    }
  }

  void _showError(Object error, {bool operationPending = false}) {
    if (!mounted) return;
    _consentDiagnostic(error);
    final authStatus =
        error is FabricGatewayException ? error.statusCode : null;
    final responseInvalid = error is FormatException ||
        error is FabricGatewayException &&
            ['PARSE_ERROR', 'INVALID_GATEWAY_RESPONSE'].contains(error.code);
    final timedOut = error is TimeoutException ||
        error is FabricGatewayException && error.code == 'TIMEOUT';
    final pending =
        error is FabricGatewayException && error.code == 'CONSENT_PENDING';
    final rejected =
        error is FabricGatewayException && error.code == 'CONSENT_REJECTED';
    final disabled = error is FabricGatewayException &&
        (error.code == 'FEATURE_DISABLED' ||
            error.message.contains('FEATURE_DISABLED'));
    if (pending && _selectedDoctor != null) {
      _pendingOutcomes.add(_selectedDoctor!.uid);
    }
    setState(() {
      _status = operationPending || pending
          ? _ConsentState.pending
          : _ConsentState.unavailable;
      _history = null;
      _proof = null;
      _error = operationPending || pending
          ? 'Your previous access change is not yet confirmed. ${pending ? 'The gateway is still checking the existing request.' : 'The blockchain service could not verify its outcome.'} Use Check request outcome to recover it. No new blockchain transaction will be submitted.'
          : rejected
              ? 'The access change was not committed. Check the current status before trying again.'
              : disabled
                  ? 'Access changes are currently disabled. No consent change has been confirmed. You can still check the current ledger status.'
                  : authStatus == 401
                      ? 'Your sign-in could not be verified by the gateway. Sign in again, then check the status.'
                      : authStatus == 403
                          ? 'The gateway did not allow this consent check. No access has been confirmed.'
                          : responseInvalid
                              ? 'The gateway returned an unreadable consent response. Consent status is unknown.'
                              : timedOut
                                  ? 'The blockchain service took too long to respond. Consent status is still unknown.'
                                  : authStatus == 404
                                      ? 'The gateway could not find the requested consent resource. Consent status is unknown.'
                                      : authStatus != null && authStatus >= 500
                                          ? 'The gateway could not complete the blockchain query. Consent status is unknown.'
                                          : 'We could not reach or verify the blockchain service. Consent status is unknown. Check the gateway connection and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: OV.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Manage Access',
            style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OV.onSurface)),
        leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.maybePop(context)),
      ),
      body: Builder(
        builder: (context) {
          final snapshot = _doctorSnapshot;
          final doctors = snapshot.data ?? <DoctorModel>[];
          final available = !snapshot.hasError &&
              doctors.any((doctor) => doctor.uid == _selectedDoctor?.uid);
          return LayoutBuilder(builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 850;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  desktop ? 32 : 20, 16, desktop ? 32 : 20, 40),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(desktop),
                      const SizedBox(height: 16),
                      if (desktop) ...[
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 3,
                                  child: _doctorCard(snapshot, doctors)),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: _statusCard(available)),
                            ]),
                        const SizedBox(height: 16),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _informationCard()),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: _proofCard(available)),
                            ]),
                      ] else ...[
                        _doctorCard(snapshot, doctors),
                        const SizedBox(height: 12),
                        _statusCard(available),
                        const SizedBox(height: 12),
                        _proofCard(available),
                        const SizedBox(height: 12),
                        _informationCard(),
                      ],
                    ]),
              )),
            );
          });
        },
      ),
    );
  }

  Widget _header(bool desktop) => Container(
        padding: EdgeInsets.all(desktop ? 20 : 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [OV.primaryContainer, OV.surfaceLowest]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OV.primary.withValues(alpha: 0.1)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (desktop) ...[
            _icon(Icons.shield_outlined, OV.primary, OV.surfaceLowest),
            const SizedBox(width: 16),
          ],
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Doctor Access & Consent',
                    style: GoogleFonts.manrope(
                        fontSize: desktop ? 26 : 23,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: OV.onSurface)),
                const SizedBox(height: 6),
                _body(
                    'You control access to your records. Select a doctor to review consent recorded through the blockchain.'),
              ])),
        ]),
      );

  Widget _doctorError(Object error) {
    final denied =
        error is FirebaseException && error.code == 'permission-denied';
    final signedOut =
        error is FirebaseException && error.code == 'unauthenticated';
    final timedOut = error is TimeoutException;
    final parsing = error is FormatException || error is TypeError;
    final code = error is FirebaseException ? error.code : null;
    return _notice(
        Icons.cloud_off_outlined,
        denied
            ? 'Doctor list access denied'
            : signedOut
                ? 'Sign in required'
                : timedOut
                    ? 'Doctor list timed out'
                    : parsing
                        ? 'Doctor profile unavailable'
                        : 'Doctors unavailable',
        denied
            ? 'Your account could not read the doctor list. Retry or contact your care team if this continues.'
            : signedOut
                ? 'Please sign in again to view registered doctors.'
                : timedOut
                    ? 'Loading is taking longer than expected. We are still listening for doctors. You can wait or retry.'
                    : parsing
                        ? 'A registered doctor profile could not be read. Retry or contact your care team.'
                        : 'We could not load the doctor list. Please retry.'
                            '${code == null ? '' : ' Service code: $code.'}');
  }

  Widget _doctorCard(
      AsyncSnapshot<List<DoctorModel>> snapshot, List<DoctorModel> doctors) {
    final selected = doctors
        .where((doctor) => doctor.uid == _selectedDoctor?.uid)
        .firstOrNull;
    return _card(children: [
      _sectionTitle('Your care team', Icons.medical_services_outlined),
      const SizedBox(height: 8),
      _body('Select a registered doctor to review their access.'),
      const SizedBox(height: 12),
      if (snapshot.hasError) ...[
        _doctorError(snapshot.error!),
        TextButton.icon(
            onPressed: () => setState(_startDoctorLoading),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry loading doctors')),
      ] else if (!snapshot.hasData) ...[
        const LinearProgressIndicator(color: OV.primary, minHeight: 3),
        const SizedBox(height: 12),
        _body('Loading registered doctors...'),
      ] else if (doctors.isEmpty)
        _notice(Icons.person_search_outlined, 'No doctors available',
            'Registered doctors will appear here when they are available.')
      else ...[
        ConsentDoctorDropdown(
          doctors: doctors,
          selectedId: selected?.uid,
          enabled: !_busy,
          onSelected: (id) =>
              _checkConsent(doctors.firstWhere((doctor) => doctor.uid == id)),
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            _icon(Icons.local_hospital_outlined, OV.secondary,
                OV.secondaryContainer),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      selected.name.isEmpty
                          ? 'Registered doctor'
                          : selected.name,
                      style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (selected.specialty.isNotEmpty)
                    _body(selected.specialty, size: 12),
                  if (selected.hospital.isNotEmpty)
                    _body(selected.hospital, size: 12),
                ])),
          ]),
        ],
      ],
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1)),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Access type',
                style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
            _badge('Direct Care', OV.primary, OV.primaryContainer),
          ]),
      const SizedBox(height: 10),
      _body(
          'Direct care allows the selected doctor to access your records for your clinical care.',
          size: 12),
    ]);
  }

  Widget _statusCard(bool available) {
    final state = !available && _selectedDoctor != null
        ? _ConsentState.unavailable
        : _status;
    final projectionRetry = _projectionRetries[_selectedDoctor?.uid];
    final label = _mutating
        ? (_recovering ? 'Checking outcome' : 'Submitting')
        : switch (state) {
            _ConsentState.unselected => 'Select a doctor',
            _ConsentState.checking => 'Checking',
            _ConsentState.pending => 'Pending',
            _ConsentState.active => 'Active',
            _ConsentState.revoked => 'Revoked',
            _ConsentState.none => 'No Consent',
            _ConsentState.expired => 'Expired',
            _ConsentState.unavailable => 'Unavailable',
          };
    final color = state == _ConsentState.active
        ? OV.tertiary
        : state == _ConsentState.revoked
            ? OV.error
            : OV.secondary;
    final tint = state == _ConsentState.active
        ? OV.tertiaryContainer
        : state == _ConsentState.revoked
            ? OV.errorContainer
            : OV.secondaryContainer;
    final description = switch (state) {
      _ConsentState.unselected => 'Select a doctor to check their access.',
      _ConsentState.checking => 'Checking access with Hyperledger Fabric...',
      _ConsentState.pending => _error ??
          'The access change is not yet confirmed. Check the existing request outcome; do not submit another access change.',
      _ConsentState.active =>
        'The ledger confirms active Direct Care consent for this doctor.',
      _ConsentState.revoked =>
        'The ledger confirms that consent for this doctor has been revoked.',
      _ConsentState.none =>
        'The ledger has no Direct Care consent for this doctor.',
      _ConsentState.expired =>
        'The ledger reports that this consent for your doctor has expired.',
      _ConsentState.unavailable => available
          ? (_error ??
              'Consent status could not be confirmed. Please try again.')
          : 'The selected doctor is no longer available in the current list. Select a doctor to continue.',
    };
    return _card(children: [
      _sectionTitle('Consent status', Icons.verified_user_outlined),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: state == _ConsentState.unselected
                ? OV.surface
                : tint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _badge(label, color, tint),
          const SizedBox(height: 12),
          _body(_mutating && !_recovering
              ? 'Waiting for the gateway to confirm the transaction. Please keep this page open.'
              : description),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child:
                    LinearProgressIndicator(minHeight: 3, color: OV.primary)),
        ]),
      ),
      if (available && !_busy) ...[
        const SizedBox(height: 18),
        if (projectionRetry != null)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _body(
                'Consent is confirmed on blockchain. The application access update still needs to synchronize.'),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: () => _changeAccess(grant: projectionRetry),
                child: const Text('Sync access update')),
          ])
        else if (_pendingOutcomes.contains(_selectedDoctor?.uid))
          OutlinedButton.icon(
              onPressed: _recoverAccess,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check request outcome'))
        else if (state == _ConsentState.active)
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _changeAccess(grant: false),
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Revoke Access'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: OV.error,
                    side: const BorderSide(color: OV.error),
                    padding: const EdgeInsets.all(18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ))
        else if (state == _ConsentState.none ||
            state == _ConsentState.revoked ||
            state == _ConsentState.expired)
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _changeAccess(grant: true),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Grant Access'),
                style: FilledButton.styleFrom(
                    backgroundColor: OV.primary,
                    padding: const EdgeInsets.all(18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              )),
        Center(
            child: TextButton.icon(
          onPressed: () => _pendingOutcomes.contains(_selectedDoctor?.uid)
              ? _recoverAccess()
              : _checkConsent(_selectedDoctor!),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Check status again'),
        )),
      ],
    ]);
  }

  Widget _informationCard() => _card(children: [
        _sectionTitle('How your consent works', Icons.hub_outlined),
        const SizedBox(height: 12),
        _infoStep(Icons.touch_app_outlined, 'You stay in control',
            'Select a doctor and confirm each grant or revocation yourself.'),
        const SizedBox(height: 12),
        _infoStep(Icons.account_tree_outlined, 'Recorded on Hyperledger Fabric',
            'Smart contracts record consent changes and keep a history of grants and revocations.'),
        const SizedBox(height: 12),
        _infoStep(Icons.privacy_tip_outlined, 'Medical content stays off-chain',
            'Your medical documents are not stored on the blockchain. Consent uses pseudonymous identifiers.'),
      ]);

  String _displayConsentStatus(Object? value) => switch (value) {
        'NOT_FOUND' => 'Not Found',
        'GRANTED' => 'Granted',
        'ACTIVE' => 'Active',
        'REVOKED' => 'Revoked',
        'EXPIRED' => 'Expired',
        _ => 'Unavailable',
      };

  Widget _proofCard(bool available) {
    final proof = available ? _proof : null;
    final selected = _selectedDoctor != null;
    final verified =
        available && proof != null && _status != _ConsentState.unavailable;
    final txId = proof?['txId'];
    return _card(children: [
      _sectionTitle('Transaction proof', Icons.receipt_long_outlined),
      const SizedBox(height: 12),
      if (!selected)
        _body(
            'Choose a doctor to review blockchain consent details and history.',
            size: 12)
      else if (!available || _status == _ConsentState.unavailable)
        _body('Blockchain consent history is currently unavailable.', size: 12)
      else if (_status == _ConsentState.checking ||
          _status == _ConsentState.pending ||
          _mutating)
        _body('Waiting for a verified blockchain response.', size: 12)
      else if (verified) ...[
        _proofField('Doctor', _selectedDoctor!.name),
        _proofField('Consent status', _displayConsentStatus(proof['status'])),
        _proofField('Access scope', 'Direct Care'),
        if (txId is String && txId.isNotEmpty) _transactionField(txId),
        for (final field in {
          'timestamp': 'Recorded at',
          'expirationTimestamp': 'Expires',
          'revokedAt': 'Revoked at'
        }.entries)
          if (proof[field.key] is String &&
              (proof[field.key] as String).isNotEmpty)
            _proofField(field.value, proof[field.key] as String),
        if (_historyLoading)
          _body('Loading blockchain consent history...', size: 12)
        else if (_history == null)
          _body('Blockchain consent history is currently unavailable.',
              size: 12)
        else if (_history!.isEmpty && _status == _ConsentState.none)
          _body('No consent transactions recorded yet.', size: 12)
        else if (_history!.isEmpty)
          _body('No consent transactions recorded yet.', size: 12)
        else
          Material(
              color: Colors.transparent,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('History (${_history!.length})',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                children: [for (final entry in _history!) _historyEntry(entry)],
              )),
      ],
    ]);
  }

  Widget _historyEntry(Map<String, dynamic> entry) {
    // Fabric history returns transaction metadata and a nested consent value.
    final value = entry['value'];
    final record = value is Map ? value : entry;
    final txId = entry['txId'] ?? record['txId'];
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (record['status'] is String)
            _proofField(
                'Consent status', _displayConsentStatus(record['status'])),
          if (txId is String && txId.isNotEmpty) _transactionField(txId),
          if (entry['timestamp'] is String)
            _proofField('Recorded at', entry['timestamp'] as String),
        ]));
  }

  Widget _transactionField(String txId) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _proofField('Transaction ID', txId),
          TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: txId));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction ID copied')));
              },
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('Copy transaction ID')),
        ],
      );

  Widget _proofField(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _body(label, size: 11),
          const SizedBox(height: 5),
          SelectableText(value,
              style: GoogleFonts.robotoMono(
                  fontSize: 11, height: 1.7, color: OV.onSurface)),
        ]),
      );

  Widget _infoStep(IconData icon, String title, String detail) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icon(icon, OV.primary, OV.primaryContainer),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface)),
                const SizedBox(height: 5),
                _body(detail, size: 12),
              ])),
        ],
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: OV.surfaceLowest,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: OV.outlineVariant.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 20,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
        Icon(icon, size: 20, color: OV.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface))),
      ]);

  Widget _body(String text, {double size = 13}) => Text(text,
      style: GoogleFonts.inter(
          fontSize: size, height: 1.65, color: OV.onSurfaceVariant));

  Widget _icon(IconData icon, Color color, Color background) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: color),
      );

  Widget _badge(String text, Color color, Color background) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(100)),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _notice(IconData icon, String title, String detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: OV.outline),
          const SizedBox(height: 10),
          Text(title,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: OV.onSurface)),
          const SizedBox(height: 6),
          _body(detail, size: 12),
        ],
      );
}

/// A field-width dropdown whose popup never aligns over the selected item.
class ConsentDoctorDropdown extends StatefulWidget {
  final List<DoctorModel> doctors;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;
  const ConsentDoctorDropdown(
      {super.key,
      required this.doctors,
      required this.selectedId,
      required this.enabled,
      required this.onSelected});

  @override
  State<ConsentDoctorDropdown> createState() => _ConsentDoctorDropdownState();
}

class _ConsentDoctorDropdownState extends State<ConsentDoctorDropdown> {
  final _controller = MenuController();
  final _focus = FocusNode();
  final _anchorKey = GlobalKey();
  bool _above = false;
  double _menuHeight = 280;

  ScrollPosition? _ancestorScroll;

  void _closeOnScroll() {
    if (_controller.isOpen) _controller.close();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _ancestorScroll) {
      _ancestorScroll?.removeListener(_closeOnScroll);
      _ancestorScroll = position;
      _ancestorScroll?.addListener(_closeOnScroll);
    }
  }

  void _open() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    final box = _anchorKey.currentContext!.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final media = MediaQuery.of(context);
    final below = media.size.height -
        media.viewInsets.bottom -
        media.padding.bottom -
        rect.bottom -
        14;
    final above = rect.top - media.padding.top - 14;
    final desired = (widget.doctors.length * 48.0 + 8).clamp(0.0, 280.0);
    setState(() {
      _above = below < desired && above > below;
      _menuHeight =
          desired.clamp(0.0, (_above ? above : below).clamp(0.0, 280.0));
    });
    _controller.open();
  }

  @override
  void dispose() {
    _ancestorScroll?.removeListener(_closeOnScroll);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.doctors.where((d) => d.uid == widget.selectedId).firstOrNull;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return MenuAnchor(
        controller: _controller,
        childFocusNode: _focus,
        animated: true,
        consumeOutsideTap: true,
        crossAxisUnconstrained: false,
        alignmentOffset: Offset(0, _above ? -_menuHeight - 6 : 6),
        onOpen: () => setState(() {}),
        onClose: () => setState(() {}),
        style: MenuStyle(
          alignment: _above
              ? AlignmentDirectional.topStart
              : AlignmentDirectional.bottomStart,
          backgroundColor: const WidgetStatePropertyAll(OV.surfaceLowest),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
          minimumSize: WidgetStatePropertyAll(Size(width, 0)),
          maximumSize: WidgetStatePropertyAll(Size(width, _menuHeight)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side:
                  BorderSide(color: OV.outlineVariant.withValues(alpha: 0.6)))),
        ),
        menuChildren: [
          for (final doctor in widget.doctors)
            MenuItemButton(
              autofocus:
                  doctor.uid == (widget.selectedId ?? widget.doctors.first.uid),
              key: ValueKey('consent-doctor-option-${doctor.uid}'),
              style: ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(width, 48)),
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16)),
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused) ||
                            doctor.uid == widget.selectedId
                        ? OV.primaryContainer
                        : OV.surfaceLowest),
              ),
              onPressed: () => widget.onSelected(doctor.uid),
              child: SizedBox(
                  width: (width - 32).clamp(0, double.infinity),
                  child: Text(
                      doctor.name.isEmpty ? 'Registered doctor' : doctor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: doctor.uid == widget.selectedId
                              ? OV.primary
                              : OV.onSurface,
                          fontWeight: doctor.uid == widget.selectedId
                              ? FontWeight.w600
                              : FontWeight.w400))),
            ),
        ],
        builder: (context, controller, child) => Focus(
          onKeyEvent: (_, event) {
            if (widget.enabled &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (!controller.isOpen) _open();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            label: 'Registered doctor',
            expanded: controller.isOpen,
            child: OutlinedButton(
              key: _anchorKey,
              focusNode: _focus,
              onPressed: widget.enabled ? _open : null,
              style: ButtonStyle(
                backgroundColor: const WidgetStatePropertyAll(OV.surfaceLowest),
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
                side: WidgetStateProperty.resolveWith((states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? OV.primary
                        : OV.outlineVariant,
                    width: states.contains(WidgetState.focused) ? 2 : 1)),
              ),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Registered doctor',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: OV.outline)),
                      const SizedBox(height: 3),
                      Text(selected == null ? 'Choose a doctor' : selected.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 14, color: OV.onSurface)),
                    ])),
                const SizedBox(width: 8),
                Icon(
                    controller.isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: OV.primary),
              ]),
            ),
          ),
        ),
      );
    });
  }
}
