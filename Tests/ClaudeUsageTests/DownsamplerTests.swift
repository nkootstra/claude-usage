import Testing
import Foundation
@testable import ClaudeUsageCore

@Suite("Downsampler")
struct DownsamplerTests {

    private func makePoints(count: Int) -> [UsageDataPoint] {
        (0..<count).map { i in
            UsageDataPoint(
                timestamp: Date().addingTimeInterval(Double(i) * 60),
                fiveHourUtilization: Double(i),
                sevenDayUtilization: Double(i) / 2
            )
        }
    }

    @Test("Returns all points when below target")
    func belowTarget() {
        let points = makePoints(count: 50)
        let result = Downsampler.downsample(points, targetCount: 200)
        #expect(result.count == 50)
    }

    @Test("Reduces to target count")
    func reducesToTarget() {
        let points = makePoints(count: 1000)
        let result = Downsampler.downsample(points, targetCount: 200)
        #expect(result.count == 200)
    }

    @Test("Preserves time order")
    func preservesOrder() {
        let points = makePoints(count: 500)
        let result = Downsampler.downsample(points, targetCount: 100)
        for i in 1..<result.count {
            #expect(result[i].timestamp >= result[i - 1].timestamp)
        }
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let result = Downsampler.downsample([], targetCount: 200)
        #expect(result.isEmpty)
    }

    @Test("Single point returns single point")
    func singlePoint() {
        let points = makePoints(count: 1)
        let result = Downsampler.downsample(points, targetCount: 200)
        #expect(result.count == 1)
    }
}
