import Foundation

public enum Downsampler {
    /// Reduce data points to targetCount using bucket averaging (single-pass per bucket).
    public static func downsample(_ points: [UsageDataPoint], targetCount: Int = 200) -> [UsageDataPoint] {
        guard points.count > targetCount else { return points }

        let bucketSize = Double(points.count) / Double(targetCount)
        var result: [UsageDataPoint] = []
        result.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), points.count)
            let bucket = points[start..<end]

            guard !bucket.isEmpty else { continue }

            var sumTime = 0.0
            var sum5h = 0.0
            var sum7d = 0.0
            for point in bucket {
                sumTime += point.timestamp.timeIntervalSince1970
                sum5h += point.fiveHourUtilization
                sum7d += point.sevenDayUtilization
            }
            let count = Double(bucket.count)

            result.append(UsageDataPoint(
                timestamp: Date(timeIntervalSince1970: sumTime / count),
                fiveHourUtilization: sum5h / count,
                sevenDayUtilization: sum7d / count
            ))
        }

        return result
    }
}
