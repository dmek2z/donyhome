import Foundation

/// 맥 알림 문구. 상태마다 말투를 다르게 하되 앱이 실제로 하지 않는 동작은 약속하지 않는다.
public enum NoticeCopy {
    public struct Message: Equatable, Sendable { public let title: String; public let body: String }
    public enum Overload: Sendable { case cpu, memory, both }

    public static func overload(_ kind: Overload, variant: Int = 0) -> Message {
        let pick = abs(variant) % 2
        switch kind {
        case .cpu:
            return [Message(title: "도니홈 · CPU가 땀 흘리는 중 😅", body: "30초 넘게 풀가동이에요. CPU · 메모리에서 무거운 앱을 찾아 쉬게 해주세요."),
                    Message(title: "도니홈 · CPU가 헉헉대요 💦", body: "한참 달리는 중이에요. 누가 힘을 쓰고 있는지 CPU · 메모리에서 볼까요?")][pick]
        case .memory:
            return [Message(title: "도니홈 · 메모리가 꽉 찼어요 🥵", body: "30초 넘게 숨이 차요. 안 쓰는 앱 몇 개만 닫아도 한결 편해져요."),
                    Message(title: "도니홈 · 메모리가 빵빵해요 🎈", body: "터지기 전에 CPU · 메모리에서 메모리를 많이 쓰는 앱을 확인해 주세요.")][pick]
        case .both:
            return Message(title: "도니홈 · CPU도 메모리도 헉헉대요 🥵", body: "30초 넘게 둘 다 바빠요. CPU · 메모리에서 범인을 찾아볼까요?")
        }
    }

    public static func storage(_ health: StorageHealth, availableText: String, variant: Int = 0) -> Message {
        switch health {
        case .critical:
            return Message(title: "도니홈 · 저장 공간이 바닥났어요 🚨", body: "남은 공간 \(availableText)뿐이에요. 지금 정리하지 않으면 Mac이 답답해질 수 있어요. 홈에서 정리할 항목을 확인하세요.")
        default:
            return [Message(title: "도니홈 · 저장 공간이 슬슬 좁아져요 🧹", body: "남은 공간 \(availableText). 도니가 정리할 거리를 찾아볼게요. 홈에서 확인해 보세요."),
                    Message(title: "도니홈 · Mac이 짐을 이고 있어요 📦", body: "남은 공간 \(availableText). 홈에서 정리 추천을 확인하고 한 번 비워 볼까요?")][abs(variant) % 2]
        }
    }
}
