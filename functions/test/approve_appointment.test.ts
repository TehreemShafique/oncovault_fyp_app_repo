// functions/test/approve_appointment.test.ts

import {
  toPktDate,
  getPktNow,
  parse12Hour,
  format12Hour,
  isValidIsoDate,
  isValidSlotKey,
  buildSlotKey,
  isSlotExpired,
  PKT_OFFSET_MS,
} from '../src/utils/time_utils';
import {
  parseDoctorAvailability,
  validateSlot,
  AppointmentInterval,
  generateDaySlots,
} from '../src/utils/availability_validator';

describe('Phase 2D.2A Trusted Clock & Time Utilities', () => {
  test('PKT offset is strictly UTC+05:00', () => {
    expect(PKT_OFFSET_MS).toBe(5 * 60 * 60 * 1000);
  });

  test('toPktDate correctly shifts UTC to PKT calendar components', () => {
    // 2026-10-15T19:30:00Z -> in PKT (+5h) becomes 2026-10-16T00:30:00
    const utcDate = new Date('2026-10-15T19:30:00Z');
    const pkt = toPktDate(utcDate);
    expect(pkt.dateKey).toBe('2026-10-16');
    expect(pkt.dayMinutes).toBe(30); // 00:30 AM
    expect(pkt.year).toBe(2026);
    expect(pkt.month).toBe(10);
    expect(pkt.day).toBe(16);
    expect(pkt.weekday).toBe(5); // Friday
  });

  test('parse12Hour and format12Hour maintain exact round-trip symmetry', () => {
    const testCases = [
      { minutes: 0, text: '12:00 AM' },
      { minutes: 540, text: '09:00 AM' },
      { minutes: 585, text: '09:45 AM' },
      { minutes: 720, text: '12:00 PM' },
      { minutes: 810, text: '01:30 PM' },
      { minutes: 1020, text: '05:00 PM' },
      { minutes: 1439, text: '11:59 PM' },
    ];

    for (const tc of testCases) {
      expect(format12Hour(tc.minutes)).toBe(tc.text);
      expect(parse12Hour(tc.text)).toBe(tc.minutes);
    }
  });

  test('isValidIsoDate validates Gregorian leap years strictly', () => {
    expect(isValidIsoDate('2024-02-29')).toBe(true); // 2024 is leap year
    expect(isValidIsoDate('2026-02-29')).toBe(false); // 2026 is NOT leap year
    expect(isValidIsoDate('2026-02-28')).toBe(true);
    expect(isValidIsoDate('2026-04-31')).toBe(false); // April has 30 days
    expect(isValidIsoDate('2026-12-31')).toBe(true);
    expect(isValidIsoDate('invalid-date')).toBe(false);
  });

  test('isValidSlotKey and buildSlotKey produce canonical keys', () => {
    expect(isValidSlotKey('2026-10-20_09:30 AM')).toBe(true);
    expect(isValidSlotKey('2026-10-20_09:30')).toBe(false);
    expect(isValidSlotKey('2026-02-29_09:30 AM')).toBe(false);

    const key = buildSlotKey('2026-10-20', '09:30 AM');
    expect(key).toBe('2026-10-20_09:30 AM');
  });

  test('isSlotExpired detects past dates, past intra-day slots, and future slots accurately', () => {
    // Simulated reference instant: 2026-10-15 14:30 PKT (09:30 UTC)
    // 14:30 PKT is 14 * 60 + 30 = 870 minutes
    const refDateUtc = new Date('2026-10-15T09:30:00Z');
    const refMs = refDateUtc.getTime();

    // 1. Yesterday is expired
    expect(isSlotExpired('2026-10-14', '09:00 AM', refMs)).toBe(true);

    // 2. Tomorrow is not expired
    expect(isSlotExpired('2026-10-16', '09:00 AM', refMs)).toBe(false);

    // 3. Today earlier slot (02:00 PM = 840 min <= 870 min) is expired
    expect(isSlotExpired('2026-10-15', '02:00 PM', refMs)).toBe(true);

    // 4. Today exact current minute (02:30 PM = 870 min <= 870 min) has started/expired
    expect(isSlotExpired('2026-10-15', '02:30 PM', refMs)).toBe(true);

    // 5. Today later slot (03:00 PM = 900 min > 870 min) is NOT expired
    expect(isSlotExpired('2026-10-15', '03:00 PM', refMs)).toBe(false);
  });
});

describe('Phase 2D.2A Availability Validator & Interval Overlap', () => {
  const structuredDoctorDoc = {
    availability: {
      slotDurationMinutes: 45,
      weeklySchedule: {
        monday: { enabled: true, startTime: '09:00', endTime: '17:00' },
        tuesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
        wednesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
        thursday: { enabled: true, startTime: '09:00', endTime: '17:00' },
        friday: { enabled: true, startTime: '09:00', endTime: '17:00' },
        saturday: { enabled: false, startTime: '09:00', endTime: '17:00' },
        sunday: { enabled: false, startTime: '09:00', endTime: '17:00' },
      },
      blockedDates: ['2026-10-25'],
      blockedSlots: ['2026-10-20_11:15 AM'],
    },
  };

  test('parses structured availability correctly', () => {
    const avail = parseDoctorAvailability(structuredDoctorDoc);
    expect(avail.state).toBe('structured');
    expect(avail.slotDurationMinutes).toBe(45);
    expect(avail.blockedDates.has('2026-10-25')).toBe(true);
    expect(avail.blockedSlots.has('2026-10-20_11:15 AM')).toBe(true);
    expect(avail.weeklySchedule.days.monday.enabled).toBe(true);
    expect(avail.weeklySchedule.days.sunday.enabled).toBe(false);
  });

  test('parses legacy availability correctly', () => {
    const legacyDoc = {
      availableDays: ['Mon', 'Tue', 'Wed'],
      availableSlots: ['09:00 AM', '10:30 AM'],
    };
    const avail = parseDoctorAvailability(legacyDoc);
    expect(avail.state).toBe('legacy');
    expect(avail.legacyDays).toEqual(['Mon', 'Tue', 'Wed']);
    expect(avail.legacySlots).toEqual(['09:00 AM', '10:30 AM']);
  });

  test('unconfigured availability fails closed', () => {
    const avail = parseDoctorAvailability({});
    expect(avail.state).toBe('unconfigured');
    const result = validateSlot({
      dateKey: '2026-10-20',
      weekday: 2,
      timeSlot: '09:00 AM',
      durationMinutes: 45,
      availability: avail,
    });
    expect(result.valid).toBe(false);
    expect(result.reason).toContain('not configured');
  });

  test('invalid structured availability fails closed', () => {
    const corruptDoc = {
      availability: {
        slotDurationMinutes: 999, // Invalid duration
        weeklySchedule: {},
        blockedDates: [],
        blockedSlots: [],
      },
    };
    const avail = parseDoctorAvailability(corruptDoc);
    expect(avail.state).toBe('invalid');
    const result = validateSlot({
      dateKey: '2026-10-20',
      weekday: 2,
      timeSlot: '09:00 AM',
      durationMinutes: 45,
      availability: avail,
    });
    expect(result.valid).toBe(false);
    expect(result.reason).toContain('malformed or invalid');
  });

  test('blocked date and blocked slot are rejected', () => {
    const avail = parseDoctorAvailability(structuredDoctorDoc);

    // Blocked date test
    const blockedDateRes = validateSlot({
      dateKey: '2026-10-25',
      weekday: 7, // Sunday
      timeSlot: '09:00 AM',
      durationMinutes: 45,
      availability: avail,
      referenceNowMs: new Date('2026-10-01T00:00:00Z').getTime(),
    });
    expect(blockedDateRes.valid).toBe(false);
    expect(blockedDateRes.reason).toContain('Date 2026-10-25 is blocked');

    // Blocked slot test
    const blockedSlotRes = validateSlot({
      dateKey: '2026-10-20',
      weekday: 2, // Tuesday
      timeSlot: '11:15 AM',
      durationMinutes: 45,
      availability: avail,
      referenceNowMs: new Date('2026-10-01T00:00:00Z').getTime(),
    });
    expect(blockedSlotRes.valid).toBe(false);
    expect(blockedSlotRes.reason).toContain('individually blocked');
  });

  test('generates valid 45-minute slots within 09:00 to 17:00 window', () => {
    const day = {
      enabled: true,
      startTime: '09:00',
      endTime: '17:00',
      startMinutes: 540,
      endMinutes: 1020,
    };
    const slots = generateDaySlots(day, 45);
    expect(slots[0]).toBe('09:00 AM');
    expect(slots[1]).toBe('09:45 AM');
    expect(slots[2]).toBe('10:30 AM');
    expect(slots[3]).toBe('11:15 AM');
    expect(slots[4]).toBe('12:00 PM');
    expect(slots[5]).toBe('12:45 PM');
    expect(slots[6]).toBe('01:30 PM');
    expect(slots[7]).toBe('02:15 PM');
    expect(slots[8]).toBe('03:00 PM');
    expect(slots[9]).toBe('03:45 PM');
    expect(slots.length).toBe(10); // 8 hours = 480m. 10 * 45m = 450m <= 480m. 30m remainder.
  });

  test('temporarily unavailable doctor rejects all slots', () => {
    const avail = parseDoctorAvailability(structuredDoctorDoc);
    const result = validateSlot({
      dateKey: '2026-10-20',
      weekday: 2,
      timeSlot: '09:00 AM',
      durationMinutes: 45,
      availability: avail,
      isDoctorAvailable: false,
      referenceNowMs: new Date('2026-10-01T00:00:00Z').getTime(),
    });
    expect(result.valid).toBe(false);
    expect(result.reason).toContain('temporarily marked as unavailable');
  });

  test('AppointmentInterval overlaps detection handles all intersection cases', () => {
    const a1 = AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 45)!; // 540..585
    const a2 = AppointmentInterval.fromSlot('2026-10-20', '09:30 AM', 45)!; // 570..615 (Partial overlap)
    const a3 = AppointmentInterval.fromSlot('2026-10-20', '09:45 AM', 45)!; // 585..630 (Abutting, NO overlap)
    const a4 = AppointmentInterval.fromSlot('2026-10-20', '09:15 AM', 15)!; // 555..570 (Contained inside a1)
    const a5 = AppointmentInterval.fromSlot('2026-10-21', '09:00 AM', 45)!; // Different date (NO overlap)

    expect(a1.overlaps(a2)).toBe(true);
    expect(a2.overlaps(a1)).toBe(true);

    expect(a1.overlaps(a4)).toBe(true);
    expect(a4.overlaps(a1)).toBe(true);

    // Abutting half-open intervals [540, 585) and [585, 630) do NOT overlap
    expect(a1.overlaps(a3)).toBe(false);
    expect(a3.overlaps(a1)).toBe(false);

    // Different calendar dates NEVER overlap
    expect(a1.overlaps(a5)).toBe(false);
  });
});

describe('Phase 2D.2A approveAppointment Callable Handler Verification', () => {
  const { approveAppointmentHandler } = require('../src/approve_appointment');

  test('rejects unauthenticated request fail-closed', async () => {
    await expect(
      approveAppointmentHandler({
        auth: undefined,
        data: { appointmentId: 'appt_1' },
      })
    ).rejects.toThrow('Doctor approval requires an authenticated session.');
  });

  test('rejects request with empty appointmentId fail-closed', async () => {
    await expect(
      approveAppointmentHandler({
        auth: { uid: 'doc_1' },
        data: { appointmentId: '' },
      })
    ).rejects.toThrow('Appointment approval requires a non-empty appointmentId.');
  });

  test('rejects caller when user document does not exist', async () => {
    const mockDb = {
      collection: jest.fn().mockReturnValue({
        doc: jest.fn().mockReturnValue({
          get: jest.fn().mockResolvedValue({ exists: false }),
        }),
      }),
    };

    await expect(
      approveAppointmentHandler(
        {
          auth: { uid: 'doc_missing' },
          data: { appointmentId: 'appt_1' },
        },
        mockDb as any
      )
    ).rejects.toThrow('Caller user profile does not exist.');
  });

  test('rejects caller when role is patient (non-doctor privilege bypass attempt)', async () => {
    const mockDb = {
      collection: jest.fn().mockReturnValue({
        doc: jest.fn().mockReturnValue({
          get: jest.fn().mockResolvedValue({
            exists: true,
            data: () => ({ role: 'patient' }),
          }),
        }),
      }),
    };

    await expect(
      approveAppointmentHandler(
        {
          auth: { uid: 'patient_attacker' },
          data: { appointmentId: 'appt_1' },
        },
        mockDb as any
      )
    ).rejects.toThrow('Caller is not authorized as a doctor.');
  });

  test('rejects caller when doctor profile is missing in /doctors', async () => {
    const mockDb = {
      collection: jest.fn().mockImplementation((colName: string) => ({
        doc: jest.fn().mockImplementation((docId: string) => ({
          get: jest.fn().mockImplementation(async () => {
            if (colName === 'users') {
              return { exists: true, data: () => ({ role: 'doctor' }) };
            }
            if (colName === 'doctors') {
              return { exists: false }; // Missing in doctors collection
            }
            return { exists: false };
          }),
        })),
      })),
    };

    await expect(
      approveAppointmentHandler(
        {
          auth: { uid: 'doc_1' },
          data: { appointmentId: 'appt_1' },
        },
        mockDb as any
      )
    ).rejects.toThrow('Doctor profile not found in doctors collection.');
  });
});

