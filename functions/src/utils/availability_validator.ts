// functions/src/utils/availability_validator.ts

import {
  isValidIsoDate,
  isValidSlotKey,
  parse12Hour,
  format12Hour,
  isSlotExpired,
} from './time_utils';

export type DoctorAvailabilityState =
  | 'structured'
  | 'legacy'
  | 'unconfigured'
  | 'invalid';

export const CANONICAL_WEEKDAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
] as const;

export const CANONICAL_LEGACY_DAYS = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
] as const;

export const SUPPORTED_DURATIONS = [15, 20, 30, 45, 60];
export const DEFAULT_DURATION = 45;
export const MAX_BLOCKED_DATES = 365;
export const MAX_BLOCKED_SLOTS = 500;

export interface DaySchedule {
  enabled: boolean;
  startTime: string; // "HH:mm" (24-hour)
  endTime: string;   // "HH:mm" (24-hour)
  startMinutes: number;
  endMinutes: number;
}

export function parseDaySchedule(raw: any, minDurationMinutes = 0): DaySchedule | null {
  if (!raw || typeof raw !== 'object') return null;
  const { enabled, startTime, endTime } = raw;

  if (typeof enabled !== 'boolean') return null;
  if (typeof startTime !== 'string' || typeof endTime !== 'string') return null;

  const timeRegex = /^([01]\d|2[0-3]):([0-5]\d)$/;
  const startMatch = startTime.trim().match(timeRegex);
  const endMatch = endTime.trim().match(timeRegex);
  if (!startMatch || !endMatch) return null;

  const startH = parseInt(startMatch[1], 10);
  const startM = parseInt(startMatch[2], 10);
  const endH = parseInt(endMatch[1], 10);
  const endM = parseInt(endMatch[2], 10);

  const startMinutes = startH * 60 + startM;
  const endMinutes = endH * 60 + endM;

  if (enabled) {
    if (startMinutes >= endMinutes) return null;
    if (minDurationMinutes > 0 && endMinutes - startMinutes < minDurationMinutes) {
      return null;
    }
  }

  return {
    enabled,
    startTime: startTime.trim(),
    endTime: endTime.trim(),
    startMinutes,
    endMinutes,
  };
}

export interface WeeklySchedule {
  days: Record<string, DaySchedule>;
}

export function parseWeeklySchedule(raw: any, minDurationMinutes = 0): WeeklySchedule | null {
  if (!raw || typeof raw !== 'object') return null;

  const rawKeys = Object.keys(raw);
  for (const k of rawKeys) {
    if (!CANONICAL_WEEKDAYS.includes(k as any)) return null;
  }

  const days: Record<string, DaySchedule> = {};
  for (const day of CANONICAL_WEEKDAYS) {
    if (!(day in raw)) return null;
    const parsedDay = parseDaySchedule(raw[day], minDurationMinutes);
    if (!parsedDay) return null;
    days[day] = parsedDay;
  }

  return { days };
}

export class AppointmentInterval {
  constructor(
    public readonly date: string, // "YYYY-MM-DD"
    public readonly startMinutes: number, // Minutes from midnight (0–1439)
    public readonly durationMinutes: number
  ) {}

  public get endMinutes(): number {
    return this.startMinutes + this.durationMinutes;
  }

  public isValid(): boolean {
    if (!isValidIsoDate(this.date)) return false;
    if (this.durationMinutes <= 0) return false;
    if (this.startMinutes < 0) return false;
    if (this.endMinutes > 1440) return false;
    return true;
  }

  public static fromSlot(
    date: string,
    timeSlot: string,
    durationMinutes: number
  ): AppointmentInterval | null {
    if (!isValidIsoDate(date)) return null;
    const start = parse12Hour(timeSlot);
    if (start === null) return null;
    const interval = new AppointmentInterval(date, start, durationMinutes);
    return interval.isValid() ? interval : null;
  }

  /**
   * Two intervals overlap iff they share the exact calendar date
   * and their half-open minute intervals intersect:
   * a.start < b.end && b.start < a.end
   */
  public overlaps(other: AppointmentInterval): boolean {
    if (!this.isValid() || !other.isValid()) return false;
    if (this.date !== other.date) return false;
    return this.startMinutes < other.endMinutes && other.startMinutes < this.endMinutes;
  }
}

export interface DoctorAvailability {
  slotDurationMinutes: number;
  weeklySchedule: WeeklySchedule;
  blockedDates: Set<string>;
  blockedSlots: Set<string>;
  state: DoctorAvailabilityState;
  legacyDays: string[];
  legacySlots: string[];
}

export function parseDoctorAvailability(docData?: Record<string, any> | null): DoctorAvailability {
  const defaultTemplate: WeeklySchedule = {
    days: {
      monday: { enabled: true, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      tuesday: { enabled: true, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      wednesday: { enabled: true, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      thursday: { enabled: true, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      friday: { enabled: true, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      saturday: { enabled: false, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
      sunday: { enabled: false, startTime: '09:00', endTime: '17:00', startMinutes: 540, endMinutes: 1020 },
    },
  };

  const createFallback = (state: DoctorAvailabilityState): DoctorAvailability => ({
    slotDurationMinutes: DEFAULT_DURATION,
    weeklySchedule: defaultTemplate,
    blockedDates: new Set<string>(),
    blockedSlots: new Set<string>(),
    state,
    legacyDays: [],
    legacySlots: [],
  });

  if (!docData || Object.keys(docData).length === 0) {
    return createFallback('unconfigured');
  }

  // 1. Structured availability map
  if ('availability' in docData) {
    const rawAvail = docData.availability;
    if (!rawAvail || typeof rawAvail !== 'object') {
      return createFallback('invalid');
    }

    const duration = rawAvail.slotDurationMinutes;
    if (typeof duration !== 'number' || !SUPPORTED_DURATIONS.includes(duration)) {
      return createFallback('invalid');
    }

    const weekly = parseWeeklySchedule(rawAvail.weeklySchedule, duration);
    if (!weekly) {
      return createFallback('invalid');
    }

    const rawDates = rawAvail.blockedDates;
    if (!Array.isArray(rawDates) || rawDates.length > MAX_BLOCKED_DATES) {
      return createFallback('invalid');
    }
    const blockedDates = new Set<string>();
    for (const d of rawDates) {
      if (typeof d !== 'string' || !isValidIsoDate(d)) return createFallback('invalid');
      if (blockedDates.has(d)) return createFallback('invalid'); // Duplicates corrupt
      blockedDates.add(d);
    }

    const rawSlots = rawAvail.blockedSlots;
    if (!Array.isArray(rawSlots) || rawSlots.length > MAX_BLOCKED_SLOTS) {
      return createFallback('invalid');
    }
    const blockedSlots = new Set<string>();
    for (const s of rawSlots) {
      if (typeof s !== 'string' || !isValidSlotKey(s)) return createFallback('invalid');
      if (blockedSlots.has(s)) return createFallback('invalid'); // Duplicates corrupt
      blockedSlots.add(s);
    }

    return {
      slotDurationMinutes: duration,
      weeklySchedule: weekly,
      blockedDates,
      blockedSlots,
      state: 'structured',
      legacyDays: [],
      legacySlots: [],
    };
  }

  // 2. Legacy availability fields
  const rawLegacySlots = docData.availableSlots;
  const rawLegacyDays = docData.availableDays;

  if (Array.isArray(rawLegacySlots) || Array.isArray(rawLegacyDays)) {
    if (!Array.isArray(rawLegacySlots) || !Array.isArray(rawLegacyDays)) {
      return createFallback('invalid');
    }

    if (rawLegacySlots.length === 0 && rawLegacyDays.length === 0) {
      return createFallback('unconfigured');
    }

    const cleanDays: string[] = [];
    const seenDays = new Set<string>();
    for (const d of rawLegacyDays) {
      if (typeof d !== 'string' || !CANONICAL_LEGACY_DAYS.includes(d as any)) {
        return createFallback('invalid');
      }
      if (seenDays.has(d)) return createFallback('invalid');
      seenDays.add(d);
      cleanDays.push(d);
    }

    const cleanSlots: string[] = [];
    const seenSlots = new Set<string>();
    const time12hRegex = /^(0[1-9]|1[0-2]):([0-5]\d)\s+(AM|PM)$/;
    for (const s of rawLegacySlots) {
      if (typeof s !== 'string' || !time12hRegex.test(s)) {
        return createFallback('invalid');
      }
      if (seenSlots.has(s)) return createFallback('invalid');
      seenSlots.add(s);
      cleanSlots.push(s);
    }

    if (cleanDays.length === 0 || cleanSlots.length === 0) {
      return createFallback('unconfigured');
    }

    return {
      slotDurationMinutes: DEFAULT_DURATION,
      weeklySchedule: defaultTemplate,
      blockedDates: new Set<string>(),
      blockedSlots: new Set<string>(),
      state: 'legacy',
      legacyDays: cleanDays,
      legacySlots: cleanSlots,
    };
  }

  // 3. Unconfigured
  return createFallback('unconfigured');
}

/**
 * Generates available slot start times for a DaySchedule and duration.
 */
export function generateDaySlots(day: DaySchedule, durationMinutes: number): string[] {
  if (!day.enabled || durationMinutes <= 0) return [];
  if (day.endMinutes - day.startMinutes < durationMinutes) return [];

  const slots: string[] = [];
  let current = day.startMinutes;
  while (current + durationMinutes <= day.endMinutes) {
    slots.push(format12Hour(current));
    current += durationMinutes;
  }
  return slots;
}

/**
 * Validates whether a requested dateKey ("YYYY-MM-DD") and timeSlot ("09:30 AM")
 * are valid and available according to the doctor's configuration.
 */
export function validateSlot(params: {
  dateKey: string;
  weekday: number; // 1 = Monday, ..., 7 = Sunday
  timeSlot: string;
  durationMinutes: number;
  availability: DoctorAvailability;
  isDoctorAvailable?: boolean;
  referenceNowMs?: number;
}): { valid: boolean; reason?: string } {
  const {
    dateKey,
    weekday,
    timeSlot,
    durationMinutes,
    availability,
    isDoctorAvailable = true,
    referenceNowMs,
  } = params;

  if (!isDoctorAvailable) {
    return { valid: false, reason: 'Doctor is temporarily marked as unavailable' };
  }

  if (availability.state === 'unconfigured') {
    return { valid: false, reason: 'Doctor has not configured availability schedule' };
  }

  if (availability.state === 'invalid') {
    return { valid: false, reason: 'Doctor availability configuration is malformed or invalid' };
  }

  if (availability.blockedDates.has(dateKey)) {
    return { valid: false, reason: `Date ${dateKey} is blocked by doctor` };
  }

  const slotKey = `${dateKey}_${timeSlot.trim()}`;
  if (availability.blockedSlots.has(slotKey)) {
    return { valid: false, reason: `Slot ${slotKey} is individually blocked by doctor` };
  }

  if (availability.state === 'legacy') {
    const legacyDayMap: Record<number, string> = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    const dayAbbr = legacyDayMap[weekday];
    if (!dayAbbr || !availability.legacyDays.includes(dayAbbr)) {
      return { valid: false, reason: `Doctor does not consult on weekday ${dayAbbr}` };
    }
    if (!availability.legacySlots.includes(timeSlot.trim())) {
      return { valid: false, reason: `Time slot ${timeSlot} is not in doctor's legacy slots` };
    }
  } else {
    // Structured availability
    const weekdayKey = CANONICAL_WEEKDAYS[weekday - 1];
    const daySchedule = availability.weeklySchedule.days[weekdayKey];
    if (!daySchedule || !daySchedule.enabled) {
      return { valid: false, reason: `Doctor is not available on ${weekdayKey}` };
    }

    const grid = generateDaySlots(daySchedule, availability.slotDurationMinutes);
    if (!grid.includes(timeSlot.trim())) {
      return { valid: false, reason: `Time slot ${timeSlot} does not align with doctor's active schedule grid` };
    }

    const startMinutes = parse12Hour(timeSlot);
    if (startMinutes === null) {
      return { valid: false, reason: `Invalid time slot format ${timeSlot}` };
    }

    if (startMinutes + durationMinutes > daySchedule.endMinutes) {
      return { valid: false, reason: `Consultation exceeds doctor working hours on ${weekdayKey}` };
    }
  }

  // Check clock expiration
  if (isSlotExpired(dateKey, timeSlot, referenceNowMs)) {
    return { valid: false, reason: `Requested slot ${dateKey} ${timeSlot} has expired` };
  }

  return { valid: true };
}
