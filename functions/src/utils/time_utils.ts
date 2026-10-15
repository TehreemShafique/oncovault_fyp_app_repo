// functions/src/utils/time_utils.ts

export const PKT_OFFSET_MS = 5 * 60 * 60 * 1000; // UTC+05:00 (Pakistan Standard Time)

const SLOT_KEY_REGEX = /^\d{4}-\d{2}-\d{2}_(0[1-9]|1[0-2]):[0-5]\d (AM|PM)$/;
const TIME_12H_REGEX = /^(0[1-9]|1[0-2]):([0-5]\d)\s+(AM|PM)$/;
const ISO_DATE_REGEX = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/**
 * Validates exact "YYYY-MM-DD" calendar date with Gregorian calendar correctness (including leap years).
 */
export function isValidIsoDate(s?: string | null): boolean {
  if (!s) return false;
  const trimmed = s.trim();
  if (!ISO_DATE_REGEX.test(trimmed)) return false;

  const parts = trimmed.split('-');
  const y = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  const d = parseInt(parts[2], 10);
  if (isNaN(y) || isNaN(m) || isNaN(d)) return false;

  const daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  let maxDays = daysInMonth[m];
  if (m === 2) {
    const isLeap = (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0);
    if (isLeap) maxDays = 29;
  }
  return d >= 1 && d <= maxDays;
}

/**
 * Validates a canonical slotKey: "YYYY-MM-DD_hh:mm AM/PM".
 */
export function isValidSlotKey(key?: string | null): boolean {
  if (!key) return false;
  const trimmed = key.trim();
  if (!SLOT_KEY_REGEX.test(trimmed)) return false;
  const datePart = trimmed.substring(0, trimmed.indexOf('_'));
  return isValidIsoDate(datePart);
}

/**
 * Parses a 12-hour string ("09:30 AM") into total minutes from midnight (0–1439).
 */
export function parse12Hour(timeStr?: string | null): number | null {
  if (!timeStr) return null;
  const match = timeStr.trim().match(TIME_12H_REGEX);
  if (!match) return null;

  let hour = parseInt(match[1], 10);
  const minute = parseInt(match[2], 10);
  const period = match[3];

  if (period === 'PM' && hour !== 12) hour += 12;
  if (period === 'AM' && hour === 12) hour = 0;

  return hour * 60 + minute;
}

/**
 * Formats total minutes from midnight (0–1439) into a canonical 12-hour string: "hh:mm AM/PM".
 */
export function format12Hour(minutes: number): string {
  if (minutes < 0 || minutes >= 1440) {
    throw new Error(`Minutes must be in 0..1439 range, got ${minutes}`);
  }
  const h24 = Math.floor(minutes / 60);
  const m = minutes % 60;
  const period = h24 >= 12 ? 'PM' : 'AM';
  let h12 = h24 % 12;
  if (h12 === 0) h12 = 12;

  const hStr = h12.toString().padStart(2, '0');
  const mStr = m.toString().padStart(2, '0');
  return `${hStr}:${mStr} ${period}`;
}

/**
 * Converts a Date or Firestore Timestamp to PKT calendar components.
 * Weekday: 1 = Monday, 7 = Sunday (matching Dart/ISO 8601).
 */
export function toPktDate(dateInput: Date | { toMillis: () => number }): {
  dateKey: string;
  dayMinutes: number;
  weekday: number;
  year: number;
  month: number;
  day: number;
} {
  const millis = typeof (dateInput as any).toMillis === 'function'
    ? (dateInput as any).toMillis()
    : (dateInput as Date).getTime();

  // Shift to PKT wall clock
  const pktDate = new Date(millis + PKT_OFFSET_MS);

  const year = pktDate.getUTCFullYear();
  const month = pktDate.getUTCMonth() + 1;
  const day = pktDate.getUTCDate();
  const hour = pktDate.getUTCHours();
  const minute = pktDate.getUTCMinutes();

  const dateKey = `${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
  const dayMinutes = hour * 60 + minute;

  // JS getUTCDay: 0 = Sun, 1 = Mon, ..., 6 = Sat
  // Convert to ISO 8601: Mon = 1, Sun = 7
  const jsDay = pktDate.getUTCDay();
  const weekday = jsDay === 0 ? 7 : jsDay;

  return { dateKey, dayMinutes, weekday, year, month, day };
}

/**
 * Gets the current authoritative PKT instant and wall-clock date/time.
 */
export function getPktNow(referenceNowMs?: number): {
  dateKey: string;
  nowMinutes: number;
  weekday: number;
  currentInstantMs: number;
} {
  const currentInstantMs = referenceNowMs !== undefined ? referenceNowMs : Date.now();
  const { dateKey, dayMinutes, weekday } = toPktDate(new Date(currentInstantMs));
  return { dateKey, nowMinutes: dayMinutes, weekday, currentInstantMs };
}

/**
 * Builds canonical slot key: "YYYY-MM-DD_hh:mm AM/PM".
 */
export function buildSlotKey(dateInput: string | Date | { toMillis: () => number }, timeSlot: string): string {
  let dateKey: string;
  if (typeof dateInput === 'string') {
    dateKey = dateInput.trim();
  } else {
    dateKey = toPktDate(dateInput).dateKey;
  }
  return `${dateKey}_${timeSlot.trim()}`;
}

/**
 * Checks if a requested slot is expired relative to authoritative PKT server time.
 */
export function isSlotExpired(
  dateKey: string,
  timeSlot: string,
  referenceNowMs?: number
): boolean {
  const { dateKey: nowDateKey, nowMinutes } = getPktNow(referenceNowMs);

  if (dateKey < nowDateKey) {
    return true; // Past date
  }

  if (dateKey === nowDateKey) {
    const slotMinutes = parse12Hour(timeSlot);
    if (slotMinutes === null) return true;
    return slotMinutes <= nowMinutes; // Slot has already started or elapsed
  }

  return false;
}
