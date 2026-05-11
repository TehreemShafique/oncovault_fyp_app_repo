// lib/features/ehr/presentation/widgets/cbc_data_table.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/medical_record_model.dart';
import '../../../../features/ehr/data/models/cbc_report_model.dart';
import '../../../../theme/app_theme.dart';

/// CbcDataTable
/// Displays all CBC fields in a clean, color-coded table.
/// Each row shows: field name | patient value | normal range | status chip
///
/// Usage:
///   CbcDataTable(report: cbcReportModel)
///
/// SRS Reference: Mockup M4 – EHR Page, Module 5
class CbcDataTable extends StatelessWidget {
  final CbcReportModel report;

  const CbcDataTable({super.key, required this.report});

  // ─── Normal reference ranges ──────────────────────────────────
  static const Map<String, _Range> _ranges = {
    'WBC'        : _Range(min: 4.5,  max: 11.0,  unit: '10³/µL'),
    'RBC'        : _Range(min: 4.2,  max: 5.9,   unit: '10⁶/µL'),
    'Hemoglobin' : _Range(min: 12.0, max: 17.5,  unit: 'g/dL'),
    'Hematocrit' : _Range(min: 36.0, max: 50.0,  unit: '%'),
    'MCV'        : _Range(min: 80.0, max: 100.0, unit: 'fL'),
    'MCH'        : _Range(min: 27.0, max: 33.0,  unit: 'pg'),
    'MCHC'       : _Range(min: 32.0, max: 36.0,  unit: 'g/dL'),
    'Platelets'  : _Range(min: 150.0,max: 400.0, unit: '10³/µL'),
    'Neutrophils': _Range(min: 40.0, max: 70.0,  unit: '%'),
    'Lymphocytes': _Range(min: 20.0, max: 45.0,  unit: '%'),
  };

  // ─── Build rows from report ───────────────────────────────────
  List<_CbcRow> get _rows => [
    _CbcRow(label: 'WBC',         value: report.wbc),
    _CbcRow(label: 'RBC',         value: report.rbc),
    _CbcRow(label: 'Hemoglobin',  value: report.hemoglobin),
    _CbcRow(label: 'Hematocrit',  value: report.hematocrit),
    _CbcRow(label: 'MCV',         value: report.mcv),
    _CbcRow(label: 'MCH',         value: report.mch),
    _CbcRow(label: 'MCHC',        value: report.mchc),
    _CbcRow(label: 'Platelets',   value: report.platelets),
    _CbcRow(label: 'Neutrophils', value: report.neutrophils),
    _CbcRow(label: 'Lymphocytes', value: report.lymphocytes),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow   : [
          BoxShadow(
            color    : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset   : const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CBC Results',
                  style: GoogleFonts.manrope(
                    fontSize  : 16,
                    fontWeight: FontWeight.w700,
                    color     : OV.onSurface,
                  ),
                ),
                Text(
                  'Test Date: ${_formatDate(report.testDate)}',
                  style: GoogleFonts.inter(
                    fontSize : 11,
                    color    : OV.outline,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Column labels ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'PARAMETER',
                    style: _headerStyle,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'VALUE',
                    style: _headerStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'NORMAL RANGE',
                    style: _headerStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'STATUS',
                    style: _headerStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Divider ────────────────────────────────────────────
          Divider(
            height   : 1,
            thickness: 1,
            color    : OV.outlineVariant.withOpacity(0.4),
          ),

          // ── Rows ───────────────────────────────────────────────
          ListView.separated(
            shrinkWrap    : true,
            physics       : const NeverScrollableScrollPhysics(),
            itemCount     : _rows.length,
            separatorBuilder: (_, __) => Divider(
              height   : 1,
              thickness: 1,
              indent   : 20,
              endIndent: 20,
              color    : OV.outlineVariant.withOpacity(0.25),
            ),
            itemBuilder: (context, index) {
              final row   = _rows[index];
              final range = _ranges[row.label];
              final status = range?.statusFor(row.value) ?? _CbcStatus.normal;

              return _CbcRowTile(
                row   : row,
                range : range,
                status: status,
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Legend ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Row(
              children: [
                _LegendDot(color: _CbcStatus.normal.color,  label: 'Normal'),
                const SizedBox(width: 16),
                _LegendDot(color: _CbcStatus.low.color,    label: 'Low'),
                const SizedBox(width: 16),
                _LegendDot(color: _CbcStatus.high.color,   label: 'High'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => GoogleFonts.inter(
    fontSize     : 10,
    fontWeight   : FontWeight.w700,
    color        : OV.outline,
    letterSpacing: 0.8,
  );

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
}

// ════════════════════════════════════════════════════════════════
// ROW TILE
// ════════════════════════════════════════════════════════════════
class _CbcRowTile extends StatelessWidget {
  final _CbcRow    row;
  final _Range?    range;
  final _CbcStatus status;

  const _CbcRowTile({
    required this.row,
    required this.range,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    // Highlight entire row if abnormal
    final Color rowBg = status == _CbcStatus.normal
        ? Colors.transparent
        : status.color.withOpacity(0.04);

    return Container(
      color  : rowBg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      child  : Row(
        children: [
          // Parameter name
          Expanded(
            flex: 3,
            child: Text(
              row.label,
              style: GoogleFonts.inter(
                fontSize  : 13,
                fontWeight: FontWeight.w500,
                color     : OV.onSurface,
              ),
            ),
          ),

          // Value
          Expanded(
            flex: 2,
            child: Text(
              row.value.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize  : 13,
                fontWeight: FontWeight.w700,
                color     : status.color,
              ),
            ),
          ),

          // Normal range + unit
          Expanded(
            flex: 3,
            child: Text(
              range != null
                  ? '${range!.min}–${range!.max} ${range!.unit}'
                  : '—',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color   : OV.outline,
                height  : 1.4,
              ),
            ),
          ),

          // Status chip
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child    : _StatusChip(status: status),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// STATUS CHIP
// ════════════════════════════════════════════════════════════════
class _StatusChip extends StatelessWidget {
  final _CbcStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color       : status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.inter(
          fontSize  : 10,
          fontWeight: FontWeight.w700,
          color     : status.color,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LEGEND DOT
// ════════════════════════════════════════════════════════════════
class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width : 8,
          height: 8,
          decoration: BoxDecoration(
            color : color,
            shape : BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color   : OV.outline,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ════════════════════════════════════════════════════════════════

class _CbcRow {
  final String label;
  final double value;
  const _CbcRow({required this.label, required this.value});
}

class _Range {
  final double min;
  final double max;
  final String unit;

  const _Range({
    required this.min,
    required this.max,
    required this.unit,
  });

  String get display => '$min–$max $unit';

  _CbcStatus statusFor(double value) {
    if (value < min) return _CbcStatus.low;
    if (value > max) return _CbcStatus.high;
    return _CbcStatus.normal;
  }
}

enum _CbcStatus { normal, low, high }

extension _CbcStatusX on _CbcStatus {
  String get label {
    switch (this) {
      case _CbcStatus.normal: return 'Normal';
      case _CbcStatus.low:    return 'Low';
      case _CbcStatus.high:   return 'High';
    }
  }

  Color get color {
    switch (this) {
      case _CbcStatus.normal: return const Color(0xFF1B6B3A);
      case _CbcStatus.low:    return const Color(0xFFB8860B);
      case _CbcStatus.high:   return const Color(0xFFB00020);
    }
  }
}