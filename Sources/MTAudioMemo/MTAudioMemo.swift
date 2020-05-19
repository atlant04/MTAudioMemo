//
//  MTAudioMemo.swift
//  AudioMemos
//
//  Created by Maksim Tochilkin on 18.05.2020.
//  Copyright © 2020 Maksim Tochilkin. All rights reserved.
//

import UIKit
import AVFoundation


@IBDesignable
class Track: UIView {
    var points: [Float] = []
    var bars: [CAShapeLayer] = []
    @IBInspectable var barStroke: UIColor = .black
    @IBInspectable var numberOfSamples: Int = 20
    @IBInspectable var barHeight: CGFloat = 15
    @IBInspectable var peek: Float = 10
    
    override func draw(_ rect: CGRect) {
        let spacing = bounds.width / CGFloat(numberOfSamples)
        var offset: CGFloat = spacing / 4
        let rect = CGRect(x: 0, y: 0, width: spacing / 4, height: barHeight)
        let path = UIBezierPath(rect: rect).cgPath
        
        for index in 0 ..< numberOfSamples {
            let layer = bars[index]
            layer.path = path.copy()
            layer.position = CGPoint(x: offset, y: bounds.midY - barHeight / 2)
            offset += spacing
        }

    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    
    func commonInit() {
        for _ in 0 ..< numberOfSamples {
            let bar = CAShapeLayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bars.append(bar)
            self.layer.addSublayer(bar)
        }
    }
    
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        
        let floats = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { data.pointee[$0] }
        let values = floats.batched(by: floats.count / numberOfSamples) { $0.reduce(0, +) }
        guard let max = values.max(), let min = values.min() else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (index, bar) in self.bars.enumerated() {
                let scale = values[index].map(from: min...max, to: -1...1)
                guard !scale.isNaN else { break } 
                let midY = self.bounds.midY
                let scaleForScale = (max - min).map(from: 0...self.peek, to: 0...1)
                print(scale)
                bar.frame.origin.y = midY - midY * CGFloat(scale * Swift.min(scaleForScale, 1))
            }
        }
    }
    
    func resetBars() {
        for bar in bars {
            bar.frame.origin.y = bounds.midY - barHeight / 2
        }
    }
    
}

class AudioMemo: UIView, AVAudioRecorderDelegate {
    var playButton = PlayButton()
    var track = Track()
    var session: AVAudioSession!
    var recorder: AVAudioRecorder!
    var engine = AVAudioEngine()
    var player = AVAudioPlayerNode()
    var state: State = .none
    @IBInspectable var fillColor: UIColor = .lightGray

    var currentNode: AVAudioNode? {
        switch state {
        case .isPlaying:
            return player
        case .isRecording:
            return engine.inputNode
        default:
            return nil
        }
    }

    enum State {
        case none, isPlaying, isRecording
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    func commonInit() {
        addSubview(playButton)
        addSubview(track)
    
        playButton.translatesAutoresizingMaskIntoConstraints = false
        track.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            playButton.heightAnchor.constraint(equalTo: heightAnchor),
            playButton.widthAnchor.constraint(equalTo: heightAnchor),
            track.leadingAnchor.constraint(equalTo: playButton.trailingAnchor),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    
        playButton.addTarget(self, action: #selector(didPressRecord), for: .valueChanged)
        self.layer.cornerRadius = 10
        self.layer.cornerCurve = .continuous
        self.backgroundColor = fillColor
        let interaction = UIContextMenuInteraction(delegate: self)
        addInteraction(interaction)

    }
    
    func play(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        player.scheduleFile(file, at: nil)
        try engine.start()
        player.play()
    }
    
    func setupRecorder() {
        session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            session.requestRecordPermission() { [unowned self] allowed in
                DispatchQueue.main.async {
                    if allowed {
                        self.loadRecordingUI()
                    } else {
                        self.loadFailUI()
                    }
                }
            }
        } catch {
            self.loadFailUI()
        }
    }
    
    func loadRecordingUI() {
        
    }
    
    func loadFailUI() {
        
    }
    
    class func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }

    class func getWhistleURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent("whistle.m4a")
    }
    
    func buildWaveForm(tap node: AVAudioNode) throws {
        let format = node.outputFormat(forBus: 0)
        
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] (buffer, time) in
            self?.track.process(buffer)
        }
        engine.prepare()
    }
    
    func record(_ url: URL) throws {
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        try engine.start()

    }
    
    func finishRecording(success: Bool) {

        currentNode?.removeTap(onBus: 0)
        state = .none
        track.resetBars()
        
        engine.stop()
        recorder?.stop()
        player.stop()
        
        recorder = nil

        if success {
          
        } else {

        }
    }
    
    @objc
    func didPressRecord() {
        guard state != .none, let currentNode = currentNode else { return }
        
        if engine.isRunning {
            finishRecording(success: true)
            return
        }
        
        do {
            if state == .isPlaying {
                try play(AudioMemo.getWhistleURL())
            } else if state == .isRecording {
                try record(AudioMemo.getWhistleURL())
            }
           
            try buildWaveForm(tap: currentNode)
        } catch {
            finishRecording(success: true)
        }
    }
    
}




//@IBDesignable
class PlayButton: UIControl {
    @IBInspectable var fillColor: UIColor = .systemBlue
    @IBInspectable var isPlaying: Bool = true
    @IBInspectable var iconFillColor: UIColor = .systemRed
    @IBInspectable var rimWidth: CGFloat = 6
    
    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }
    
    override var layer: CAShapeLayer {
        return super.layer as! CAShapeLayer
    }
    
    override var intrinsicContentSize: CGSize {
        let side = min(bounds.width, bounds.height)
        return CGSize(width: side, height: side)
    }
    
    var circle: CGPath!
    var square: CGPath!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    func commonInit() {
        layer.fillColor = iconFillColor.cgColor
        backgroundColor = .clear
    }
    
    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = UIBezierPath(arcCenter: center, radius: radius - rimWidth / 2 - 4, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        path.lineWidth = rimWidth
        fillColor.setStroke()
        path.stroke()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if layer.path == nil {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height)
            circle = circlePathWithCenter(center: center, radius: radius / 2 - rimWidth - 8)
            square = squarePathWithCenter(center: center, side: radius / 2 - rimWidth / 2)
            layer.path = circle
        }
    }


    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let transition = CABasicAnimation(keyPath: "path")
        transition.fromValue = layer.path
        let newPath = isPlaying ? square : circle
        transition.toValue = newPath
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        transition.duration = 0.3
        transition.fillMode = .forwards
        transition.isRemovedOnCompletion = false
        isPlaying = !isPlaying
        sendActions(for: .valueChanged)
        self.layer.path = newPath
        layer.add(transition, forKey: "morphing")
 
    }
    
    func circlePathWithCenter(center: CGPoint, radius: CGFloat) -> CGPath {
        let circlePath = UIBezierPath()
        circlePath.addArc(withCenter: center, radius: radius, startAngle: -.pi, endAngle: -.pi / 2, clockwise: true)
        circlePath.addArc(withCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        circlePath.addArc(withCenter: center, radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        circlePath.addArc(withCenter: center, radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        circlePath.close()
        
        return circlePath.cgPath
    }

    func squarePathWithCenter(center: CGPoint, side: CGFloat) -> CGPath {
        let squarePath = UIBezierPath()
        let startX = center.x - side / 2
        let startY = center.y - side / 2
        squarePath.move(to: CGPoint(x: startX, y: startY))
        squarePath.addLine(to: squarePath.currentPoint)
        squarePath.addLine(to: CGPoint(x: startX + side, y: startY))
        squarePath.addLine(to: squarePath.currentPoint)
        squarePath.addLine(to: CGPoint(x: startX + side, y: startY + side))
        squarePath.addLine(to: squarePath.currentPoint)
        squarePath.addLine(to: CGPoint(x: startX, y: startY + side))
        squarePath.addLine(to: squarePath.currentPoint)
        squarePath.close()
        return squarePath.cgPath
    }
}


@IBDesignable class CounterView: UIView {
    @IBInspectable var arcWidth: CGFloat = 50
    @IBInspectable var fillColor: UIColor = .systemYellow
    @IBInspectable var numberOfSections: Int = 4
    @IBInspectable var currentSection: Int = 1
    @IBInspectable var borderColor: UIColor = .blue
    
    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = max(bounds.width, bounds.height) - 8
        let startAngle: CGFloat = 3 * .pi / 4
        let endAngle: CGFloat = .pi / 4

        let path = UIBezierPath(
          arcCenter: center,
          radius: radius/2 - arcWidth/2,
          startAngle: startAngle,
          endAngle: endAngle,
          clockwise: true)

        path.lineWidth = arcWidth
        fillColor.setStroke()
        path.stroke()
        
        let angleDifference: CGFloat = 2 * .pi - startAngle + endAngle
        let anglePerSection = angleDifference / CGFloat(numberOfSections)
        let currentAngle = anglePerSection * CGFloat(currentSection) + startAngle
        
        let outerArcRadius = radius / 2
        
        let outerPath = UIBezierPath(arcCenter: center, radius: outerArcRadius, startAngle: startAngle, endAngle: currentAngle, clockwise: true)
        
        
        let innerArcRadius = radius/2 - arcWidth
        outerPath.addArc(withCenter: center, radius: innerArcRadius, startAngle: currentAngle, endAngle: startAngle, clockwise: false)
        
        outerPath.close()
        borderColor.setStroke()
        outerPath.lineWidth = 5
        outerPath.stroke()
        
    }
}



extension AudioMemo: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: { _ in
                let children: [UIMenuElement] = [self.recordAction, self.playAction]
                return UIMenu(title: "", children: children)
            })
    }
    
    var recordAction: UIAction {
        return UIAction(title: "Record") { action in
            self.state = .isRecording
        }
    }
    
    var playAction: UIAction {
        return UIAction(title: "Play") { action in
            self.state = .isPlaying
        }
    }
}





extension FloatingPoint {
    func map(from start: ClosedRange<Self>, to end: ClosedRange<Self>) -> Self {
           let slope = (self - start.lowerBound) / (start.upperBound - start.lowerBound)
           return slope * (end.upperBound - end.lowerBound) + end.lowerBound
    }
}

extension Array {
    func batched(by size: Int, map: ([Element]) -> Element) -> [Element] {
        return stride(from: 0, to: count, by: size).map { (index: Int) -> Element in
            let arr = Array(self[index ..< Swift.min(index + size, count)])
            return map(arr)
        }
    }
}

