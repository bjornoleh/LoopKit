//
//  Guardrail+Settings.swift
//  LoopKit
//
//  Created by Rick Pasetto on 7/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit

public extension Guardrail where Value == HKQuantity {
    static let suspendThreshold = Guardrail(absoluteBounds: 67...110, recommendedBounds: 74...80, unit: .milligramsPerDeciliter, startingSuggestion: 80)

    static func maxSuspendThresholdValue(correctionRangeSchedule: GlucoseRangeSchedule?, preMealTargetRange: ClosedRange<HKQuantity>?, workoutTargetRange: ClosedRange<HKQuantity>?) -> HKQuantity {

        return [
            suspendThreshold.absoluteBounds.upperBound,
            correctionRangeSchedule?.minLowerBound(),
            preMealTargetRange?.lowerBound,
            workoutTargetRange?.lowerBound
        ]
        .compactMap { $0 }
        .min()!
    }

    static let correctionRange = Guardrail(absoluteBounds: 87...180, recommendedBounds: 101...115, unit: .milligramsPerDeciliter, startingSuggestion: 100)

    static func minCorrectionRangeValue(suspendThreshold: GlucoseThreshold?) -> HKQuantity {
        return [
            correctionRange.absoluteBounds.lowerBound,
            suspendThreshold?.quantity
        ]
        .compactMap { $0 }
        .max()!
    }
    
    fileprivate static func workoutCorrectionRange(correctionRangeScheduleRange: ClosedRange<HKQuantity>,
                                                   suspendThreshold: GlucoseThreshold?) -> Guardrail<HKQuantity> {
        // Static "unconstrained" constant values before applying constraints
        let workoutCorrectionRange = Guardrail(absoluteBounds: 85...250, recommendedBounds: 101...180, unit: .milligramsPerDeciliter)
        
        let absoluteLowerBound = [
            workoutCorrectionRange.absoluteBounds.lowerBound,
            suspendThreshold?.quantity
        ]
        .compactMap { $0 }
        .max()!
        let recommmendedLowerBound = max(absoluteLowerBound, correctionRangeScheduleRange.upperBound)
        return Guardrail(
            absoluteBounds: absoluteLowerBound...workoutCorrectionRange.absoluteBounds.upperBound,
            recommendedBounds: recommmendedLowerBound...workoutCorrectionRange.recommendedBounds.upperBound
        )
    }
    
    fileprivate static func preMealCorrectionRange(correctionRangeScheduleRange: ClosedRange<HKQuantity>,
                                                   suspendThreshold: GlucoseThreshold?) -> Guardrail<HKQuantity> {
        let premealCorrectionRangeMaximum = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 130.0)
        let absoluteLowerBound = suspendThreshold?.quantity ?? Guardrail.suspendThreshold.absoluteBounds.lowerBound
        return Guardrail(
            absoluteBounds: absoluteLowerBound...premealCorrectionRangeMaximum,
            recommendedBounds: absoluteLowerBound...min(max(absoluteLowerBound, correctionRangeScheduleRange.lowerBound), premealCorrectionRangeMaximum)
        )
    }
    
    static func correctionRangeOverride(for preset: CorrectionRangeOverrides.Preset,
                                        correctionRangeScheduleRange: ClosedRange<HKQuantity>,
                                        suspendThreshold: GlucoseThreshold?) -> Guardrail {
        
        switch preset {
        case .workout:
            return workoutCorrectionRange(correctionRangeScheduleRange: correctionRangeScheduleRange, suspendThreshold: suspendThreshold)
        case .preMeal:
            return preMealCorrectionRange(correctionRangeScheduleRange: correctionRangeScheduleRange, suspendThreshold: suspendThreshold)
        }
    }
    
    static let insulinSensitivity = Guardrail(
        absoluteBounds: 10...500,
        recommendedBounds: 16...399,
        unit: HKUnit.milligramsPerDeciliter.unitDivided(by: .internationalUnit()),
        startingSuggestion: 50
    )
 
    static let carbRatio = Guardrail(
        absoluteBounds: 2...150,
        recommendedBounds: 4...28,
        unit: .gramsPerUnit,
        startingSuggestion: 15
    )

    static func basalRate(supportedBasalRates: [Double]) -> Guardrail {
        let scheduledBasalRateAbsoluteRange = 0.05...30.0
        let allowedBasalRates = supportedBasalRates.filter { scheduledBasalRateAbsoluteRange.contains($0) }
        return Guardrail(
            absoluteBounds: allowedBasalRates.first!...allowedBasalRates.last!,
            recommendedBounds: allowedBasalRates.first!...allowedBasalRates.last!,
            unit: .internationalUnitsPerHour,
            startingSuggestion: 0
        )
    }

    static func maximumBasalRate(
        supportedBasalRates: [Double],
        scheduledBasalRange: ClosedRange<Double>?,
        lowestCarbRatio: Double?,
        maximumBasalRatePrecision decimalPlaces: Int = 3
    ) -> Guardrail {
        
        let maximumUpperBound = 70.0 / (lowestCarbRatio ?? carbRatio.absoluteBounds.lowerBound.doubleValue(for: .gramsPerUnit))
        let absoluteUpperBound = maximumUpperBound.matchingOrTruncatedValue(from: supportedBasalRates, withinDecimalPlaces: decimalPlaces)

        let recommendedHighScheduledBasalScaleFactor = 6.4
        let recommendedLowScheduledBasalScaleFactor = 2.1

        let recommendedLowerBound: Double
        let recommendedUpperBound: Double
        if let highestScheduledBasalRate = scheduledBasalRange?.upperBound {
            recommendedLowerBound = (recommendedLowScheduledBasalScaleFactor * highestScheduledBasalRate).matchingOrTruncatedValue(from: supportedBasalRates, withinDecimalPlaces: decimalPlaces)
            recommendedUpperBound = (recommendedHighScheduledBasalScaleFactor * highestScheduledBasalRate).matchingOrTruncatedValue(from: supportedBasalRates, withinDecimalPlaces: decimalPlaces)
            
            let absoluteBounds = highestScheduledBasalRate...absoluteUpperBound
            let recommendedBounds = (recommendedLowerBound...recommendedUpperBound).clamped(to: absoluteBounds)
            return Guardrail(
                absoluteBounds: absoluteBounds,
                recommendedBounds: recommendedBounds,
                unit: .internationalUnitsPerHour
            )

        } else {
            return Guardrail(
                absoluteBounds: supportedBasalRates.first!...absoluteUpperBound,
                recommendedBounds:  supportedBasalRates.first!...absoluteUpperBound,
                unit: .internationalUnitsPerHour,
                startingSuggestion: 3
            )
        }
    }

    static func maximumBolus(supportedBolusVolumes: [Double]) -> Guardrail {
        let maxBolusThresholdUnits: Double = 30
        let maxBolusWarningThresholdUnits: Double = 20
        let supportedBolusVolumes = supportedBolusVolumes.filter { $0 > 0 && $0 <= maxBolusThresholdUnits }
        let recommendedUpperBound = supportedBolusVolumes.last { $0 < maxBolusWarningThresholdUnits }
        return Guardrail(
            absoluteBounds: supportedBolusVolumes.first!...supportedBolusVolumes.last!,
            recommendedBounds: supportedBolusVolumes.dropFirst().first!...recommendedUpperBound!,
            unit: .internationalUnit(),
            startingSuggestion: 5
        )
    }
}