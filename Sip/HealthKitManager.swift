//
//  HealthKitManager.swift
//  Sip
//
//  Created by Kevin Prigge on 10/1/25.
//

import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()
    private init() {}

    private let store = HKHealthStore()
    private let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)!

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [waterType], read: [waterType])
    }

    func addWater(mL: Double, at date: Date = .now) async throws {
        let qty = HKQuantity(unit: .literUnit(with: .milli), doubleValue: mL)
        let sample = HKQuantitySample(type: waterType, quantity: qty, start: date, end: date)
        try await store.save(sample)
    }

    func todayTotalML() async throws -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let pred = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: waterType, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let ml = stats?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0
                cont.resume(returning: ml)
            }
            self.store.execute(q)
        }
    }

    func todaySampleCount() async throws -> Int {
        let start = Calendar.current.startOfDay(for: .now)
        let pred = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: waterType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.count ?? 0)
            }
            self.store.execute(q)
        }
    }
}
