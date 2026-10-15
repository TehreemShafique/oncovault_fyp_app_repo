// functions/test/update_doctor_availability.test.ts

import { updateDoctorAvailabilityHandler } from '../src/update_doctor_availability';

describe('Phase 2D.2A updateDoctorAvailability Callable Handler Verification', () => {
  const validSchedule = {
    monday: { enabled: true, startTime: '09:00', endTime: '17:00' },
    tuesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
    wednesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
    thursday: { enabled: true, startTime: '09:00', endTime: '17:00' },
    friday: { enabled: true, startTime: '09:00', endTime: '17:00' },
    saturday: { enabled: false, startTime: '09:00', endTime: '17:00' },
    sunday: { enabled: false, startTime: '09:00', endTime: '17:00' },
  };

  const validAvailability = {
    slotDurationMinutes: 45,
    weeklySchedule: validSchedule,
    blockedDates: ['2026-10-25'],
    blockedSlots: ['2026-10-20_11:15 AM'],
  };

  function createMockDb({
    userExists = true,
    userRole = 'doctor',
    doctorExists = true,
    scheduleRevision = 1,
    bookedSlots = [] as Array<{ id: string; data: Record<string, any> }>,
    onTransactionSet = (data: any) => {},
  } = {}) {
    const doctorData = {
      uid: 'doc_1',
      scheduleRevision,
      availability: validAvailability,
    };

    const mockSlotDocs = bookedSlots.map((s) => ({
      id: s.id,
      data: () => s.data,
    }));

    const mockSlotSnap = {
      empty: mockSlotDocs.length === 0,
      docs: mockSlotDocs,
    };

    const mockDoctorDoc = {
      exists: doctorExists,
      data: () => doctorData,
    };

    const mockDb = {
      collection: jest.fn().mockImplementation((col: string) => {
        if (col === 'users') {
          return {
            doc: jest.fn().mockImplementation((docId: string) => ({
              id: docId,
              get: jest.fn().mockResolvedValue({
                exists: userExists,
                data: () => ({ role: userRole }),
              }),
            })),
          };
        }
        if (col === 'doctors') {
          return {
            doc: jest.fn().mockImplementation((docId: string) => ({
              id: docId,
              get: jest.fn().mockResolvedValue(mockDoctorDoc),
            })),
          };
        }
        if (col === 'bookedSlots') {
          return {
            doc: jest.fn().mockReturnValue({
              collection: jest.fn().mockReturnValue({
                get: jest.fn().mockResolvedValue(mockSlotSnap),
              }),
            }),
          };
        }
        return {};
      }),
      runTransaction: jest.fn().mockImplementation(async (callback) => {
        const transaction = {
          get: jest.fn().mockImplementation(async (ref: any) => {
            // Distinguish collection ref (bookedSlots) vs document ref (doctor)
            if (ref && typeof ref.id === 'string' && ref.id === 'doc_1') {
              return mockDoctorDoc;
            }
            return mockSlotSnap;
          }),
          set: jest.fn().mockImplementation((ref: any, data: any, opts: any) => {
            onTransactionSet(data);
          }),
          update: jest.fn().mockImplementation((ref: any, data: any) => {
            onTransactionSet(data);
          }),
        };
        return callback(transaction);
      }),
    };

    return mockDb;
  }

  test('rejects unauthenticated request fail-closed', async () => {
    await expect(
      updateDoctorAvailabilityHandler(
        { data: { availability: validAvailability } } as any,
        createMockDb() as any
      )
    ).rejects.toThrow('Doctor availability updates require an authenticated session.');
  });

  test('rejects caller when user document does not exist', async () => {
    const mockDb = createMockDb({ userExists: false });
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_missing' },
          data: { availability: validAvailability },
        },
        mockDb as any
      )
    ).rejects.toThrow('Caller user profile does not exist.');
  });

  test('rejects caller when role is patient (non-doctor privilege bypass attempt)', async () => {
    const mockDb = createMockDb({ userRole: 'patient' });
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'patient_attacker' },
          data: { availability: validAvailability },
        },
        mockDb as any
      )
    ).rejects.toThrow('Caller is not authorized as a doctor.');
  });

  test('rejects caller when doctor profile is missing in /doctors', async () => {
    const mockDb = createMockDb({ doctorExists: false });
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: { availability: validAvailability },
        },
        mockDb as any
      )
    ).rejects.toThrow('Doctor profile not found in doctors collection.');
  });

  test('rejects request with missing or malformed availability payload', async () => {
    const mockDb = createMockDb();
    await expect(
      updateDoctorAvailabilityHandler(
        { auth: { uid: 'doc_1' }, data: {} } as any,
        mockDb as any
      )
    ).rejects.toThrow('Doctor availability update requires an availability configuration payload.');
  });

  test('rejects unsupported slotDurationMinutes (e.g. 25, 90)', async () => {
    const mockDb = createMockDb();
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              slotDurationMinutes: 25,
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('slotDurationMinutes must be one of [15, 20, 30, 45, 60]. Received: 25');
  });

  test('rejects invalid weeklySchedule (missing day or invalid hours)', async () => {
    const mockDb = createMockDb();

    // Missing friday
    const incompleteSchedule: any = { ...validSchedule };
    delete incompleteSchedule.friday;

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              weeklySchedule: incompleteSchedule,
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('weeklySchedule is malformed');

    // Invalid time range (start >= end)
    const invertedSchedule = {
      ...validSchedule,
      monday: { enabled: true, startTime: '18:00', endTime: '09:00' },
    };

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              weeklySchedule: invertedSchedule,
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('weeklySchedule is malformed');
  });

  test('rejects malformed blockedDates (non-leap year Feb 29, invalid format)', async () => {
    const mockDb = createMockDb();
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              blockedDates: ['2026-02-29'], // 2026 is not a leap year
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('Invalid blocked date format: "2026-02-29". Expected "YYYY-MM-DD".');
  });

  test('rejects malformed blockedSlots', async () => {
    const mockDb = createMockDb();
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              blockedSlots: ['2026-10-20_bad_time'],
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('Invalid blocked slot key format: "2026-10-20_bad_time". Expected "YYYY-MM-DD_hh:mm AM/PM".');
  });

  test('protects confirmed appointments when doctor tries to block confirmed date', async () => {
    const mockDb = createMockDb({
      bookedSlots: [
        {
          id: '2026-10-25_09:00 AM',
          data: {
            date: '2026-10-25',
            time: '09:00 AM',
            appointmentId: 'appt_confirmed_100',
          },
        },
      ],
    });

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              blockedDates: ['2026-10-25'], // Has confirmed appointment appt_confirmed_100
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('Cannot block date 2026-10-25: existing confirmed appointment (appt_confirmed_100) is scheduled on this date.');
  });

  test('protects confirmed appointments when doctor tries to block confirmed slot', async () => {
    const mockDb = createMockDb({
      bookedSlots: [
        {
          id: '2026-10-20_11:15 AM',
          data: {
            date: '2026-10-20',
            time: '11:15 AM',
            appointmentId: 'appt_confirmed_101',
          },
        },
      ],
    });

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              ...validAvailability,
              blockedDates: [],
              blockedSlots: ['2026-10-20_11:15 AM'],
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('Cannot block slot 2026-10-20_11:15 AM: existing confirmed appointment is scheduled at this time.');
  });

  test('protects confirmed appointments when doctor disables a weekday with confirmed appointment', async () => {
    // 2026-10-20 is a Tuesday
    const mockDb = createMockDb({
      bookedSlots: [
        {
          id: '2026-10-20_09:00 AM',
          data: {
            date: '2026-10-20',
            time: '09:00 AM',
            appointmentId: 'appt_tuesday_1',
          },
        },
      ],
    });

    const disableTuesdaySchedule = {
      ...validSchedule,
      tuesday: { enabled: false, startTime: '09:00', endTime: '17:00' },
    };

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: 'doc_1' },
          data: {
            availability: {
              slotDurationMinutes: 45,
              weeklySchedule: disableTuesdaySchedule,
              blockedDates: [],
              blockedSlots: [],
            },
          },
        },
        mockDb as any
      )
    ).rejects.toThrow('Cannot disable tuesday: existing confirmed appointment is scheduled on 2026-10-20 at 09:00 AM.');
  });

  test('successfully updates availability and increments scheduleRevision inside transaction', async () => {
    let committedUpdates: any = null;

    const mockDb = createMockDb({
      scheduleRevision: 5,
      onTransactionSet: (data) => {
        committedUpdates = data;
      },
    });

    const response = await updateDoctorAvailabilityHandler(
      {
        auth: { uid: 'doc_1' },
        data: {
          availability: validAvailability,
          isAvailable: true,
        },
      },
      mockDb as any
    );

    expect(response.success).toBe(true);
    expect(response.doctorId).toBe('doc_1');
    expect(response.scheduleRevision).toBe(6);

    expect(committedUpdates).not.toBeNull();
    expect(committedUpdates.scheduleRevision).toBe(6);
    expect(committedUpdates.isAvailable).toBe(true);
    expect(committedUpdates.availability.slotDurationMinutes).toBe(45);
    expect(committedUpdates.availableDays).toContain('Mon');
    expect(committedUpdates.availableDays).toContain('Fri');
    expect(committedUpdates.availableSlots).toContain('09:00 AM');
  });
});
