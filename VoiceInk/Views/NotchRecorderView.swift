import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var showPromptPopover = false
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                return screen.safeAreaInsets.top
            }
            return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        }
        return NSStatusBar.system.thickness
    }
    
    // Calculate exact notch width
    private var exactNotchWidth: CGFloat {
        if let screen = NSScreen.main {
            // On MacBooks with notch, safeAreaInsets.left represents half the notch width
            if screen.safeAreaInsets.left > 0 {
                // Multiply by 2 because safeAreaInsets.left is half the notch width
                return screen.safeAreaInsets.left * 2
            }
            // Fallback for non-notched Macs - use a standard width
            return 200
        }
        return 200 // Default fallback
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                HStack(spacing: 0) {
                    // Left side group with fixed width
                    HStack(spacing: 8) {
                        // Record Button
                        NotchRecordButton(
                            isRecording: whisperState.isRecording,
                            isProcessing: whisperState.isProcessing
                        ) {
                            Task { await whisperState.toggleRecord() }
                        }
                        .frame(width: 22)
                        
                        // AI Enhancement Toggle
                        if let enhancementService = whisperState.getEnhancementService() {
                            NotchToggleButton(
                                isEnabled: enhancementService.isEnhancementEnabled,
                                icon: "sparkles",
                                color: .blue
                            ) {
                                enhancementService.isEnhancementEnabled.toggle()
                            }
                            .frame(width: 22)
                            .disabled(!enhancementService.isConfigured)
                        }
                    }
                    .frame(width: 44) // Fixed width for controls
                    .padding(.leading, 16)
                    
                    // Center section with exact notch width
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: exactNotchWidth)
                        .contentShape(Rectangle()) // Make the entire area tappable
                    
                    // Right side group with fixed width
                    HStack(spacing: 8) {
                        // Custom Prompt Toggle and Selector
                        if let enhancementService = whisperState.getEnhancementService() {
                            NotchToggleButton(
                                isEnabled: enhancementService.isEnhancementEnabled,
                                icon: enhancementService.activePrompt?.icon.rawValue ?? "text.badge.checkmark",
                                color: .green
                            ) {
                                showPromptPopover.toggle()
                            }
                            .frame(width: 22)
                            .disabled(!enhancementService.isEnhancementEnabled)
                            .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                                NotchPromptPopover(enhancementService: enhancementService)
                            }
                        }
                        
                        // Visualizer
                        Group {
                            if whisperState.isProcessing {
                                NotchStaticVisualizer(color: .white)
                            } else {
                                NotchAudioVisualizer(
                                    audioMeter: recorder.audioMeter,
                                    color: .white,
                                    isActive: whisperState.isRecording
                                )
                            }
                        }
                        .frame(width: 22)
                    }
                    .frame(width: 44) // Fixed width for controls
                    .padding(.trailing, 16)
                }
                .frame(height: menuBarHeight)
                .frame(maxWidth: windowManager.isVisible ? .infinity : 0)
                .background(Color.black)
                .mask {
                    NotchShape(cornerRadius: 10)
                }
                .clipped()
                .onHover { hovering in
                    isHovering = hovering
                }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}

// Popover view for prompt selection
struct NotchPromptPopover: View {
    @ObservedObject var enhancementService: AIEnhancementService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Mode")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(enhancementService.allPrompts) { prompt in
                        NotchPromptRow(prompt: prompt, isSelected: enhancementService.selectedPromptId == prompt.id) {
                            enhancementService.setActivePrompt(prompt)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 180)
        .frame(maxHeight: 300)
        .padding(.vertical, 8)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

// Row view for each prompt
struct NotchPromptRow: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: prompt.icon.rawValue)
                    .foregroundColor(isSelected ? .green : .white.opacity(0.8))
                    .font(.system(size: 12))
                Text(prompt.title)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.system(size: 13))
                    .lineLimit(1)
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// New toggle button component matching the notch aesthetic
struct NotchToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isEnabled ? color.opacity(0.2) : Color(red: 0.4, green: 0.4, blue: 0.45).opacity(0.2))
                    .frame(width: 20, height: 20)
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isEnabled ? color : .white.opacity(0.6))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomScaleModifier: ViewModifier {
    let scale: CGFloat
    let opacity: CGFloat
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
    }
}

// Notch-specific button styles
struct NotchRecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 22, height: 22)
                
                if isProcessing {
                    ProcessingIndicator(color: .white)
                        .frame(width: 14, height: 14)
                } else if isRecording {
                    // Show white square for recording state
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                } else {
                    // Show white circle for idle state
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
    }
    
    private var buttonColor: Color {
        if isProcessing {
            return Color(red: 0.4, green: 0.4, blue: 0.45)
        } else if isRecording {
            return .red
        } else {
            // Neutral gray for idle state
            return Color(red: 0.3, green: 0.3, blue: 0.35)
        }
    }
}

struct NotchAudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool
    
    private let barCount = 5
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 18
    private let audioThreshold: CGFloat = 0.01
    
    @State private var barHeights: [BarLevel] = []
    
    struct BarLevel {
        var average: CGFloat
        var peak: CGFloat
    }
    
    init(audioMeter: AudioMeter, color: Color, isActive: Bool) {
        self.audioMeter = audioMeter
        self.color = color
        self.isActive = isActive
        _barHeights = State(initialValue: Array(repeating: BarLevel(average: minHeight, peak: minHeight), count: 5))
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                NotchVisualizerBar(
                    averageHeight: barHeights[index].average,
                    peakHeight: barHeights[index].peak,
                    color: color
                )
            }
        }
        .onChange(of: audioMeter) { newMeter in
           
            if isActive {
                updateBars()
            } else {
                resetBars()
            }
        }
    }
    
    private func updateBars() {
        for i in 0..<barCount {
            let targetHeight = calculateTargetHeight(for: i)
            let speed = CGFloat.random(in: 0.4...0.8)
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                barHeights[i].average += (targetHeight.average - barHeights[i].average) * speed
                barHeights[i].peak += (targetHeight.peak - barHeights[i].peak) * speed
            }
        }
    }
    
    private func resetBars() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            for i in 0..<barCount {
                barHeights[i].average = minHeight
                barHeights[i].peak = minHeight
            }
        }
    }
    
    private func calculateTargetHeight(for index: Int) -> BarLevel {
        let positionFactor = CGFloat(index) / CGFloat(barCount - 1)
        let curve = sin(positionFactor * .pi)
        
        let randomFactor = Double.random(in: 0.8...1.2)
        let averageBase = audioMeter.averagePower * randomFactor
        let peakBase = audioMeter.peakPower * randomFactor
        
        let averageHeight = CGFloat(averageBase) * maxHeight * 1.7 * curve
        let peakHeight = CGFloat(peakBase) * maxHeight * 1.7 * curve
        
        let finalAverage = max(minHeight, min(averageHeight, maxHeight))
        let finalPeak = max(minHeight, min(peakHeight, maxHeight))
        
        
        return BarLevel(
            average: finalAverage,
            peak: finalPeak
        )
    }
}

struct NotchVisualizerBar: View {
    let averageHeight: CGFloat
    let peakHeight: CGFloat
    let color: Color
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Average level bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.6),
                            color.opacity(0.8),
                            color
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 2, height: averageHeight)
        
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: averageHeight)
        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: peakHeight)
    }
}

struct NotchStaticVisualizer: View {
    private let barCount = 5
    private let minHeight: CGFloat = 3
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                NotchVisualizerBar(
                    averageHeight: minHeight,
                    peakHeight: minHeight,
                    color: color
                )
            }
        }
    }
}

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color
    
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
} 
