//
//  SliderView.swift
//  Shifty
//
//  Created by Nate Thompson on 5/7/17.
//
//

import Cocoa
import SwiftLog

class SliderView: NSView {

    @IBOutlet weak var shiftSlider: NSSlider!
    private let kelvinLabel = NSTextField(labelWithString: "")

    var showsKelvinValue: Bool = false {
        didSet {
            kelvinLabel.isHidden = !showsKelvinValue
            refreshKelvinLabel()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        kelvinLabel.translatesAutoresizingMaskIntoConstraints = false
        kelvinLabel.alignment = .center
        kelvinLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        kelvinLabel.textColor = .secondaryLabelColor
        kelvinLabel.isHidden = true
        addSubview(kelvinLabel)

        NSLayoutConstraint.activate([
            kelvinLabel.centerXAnchor.constraint(equalTo: shiftSlider.centerXAnchor),
            kelvinLabel.topAnchor.constraint(equalTo: shiftSlider.bottomAnchor, constant: 2),
            kelvinLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2)
        ])
        refreshKelvinLabel()
    }

    @IBAction func shiftSliderMoved(_ sender: NSSlider) {
        let event = NSApplication.shared.currentEvent
        
        if event?.type == .leftMouseUp {
            NightShiftManager.shared.colorTemperature = sender.floatValue / 100
            refreshKelvinLabel()
            
            sender.superview?.enclosingMenuItem?.menu?.cancelTracking()
            Event.sliderMoved(value: sender.floatValue).record()
            logw("Slider set to \(sender.floatValue)")
        } else {
            NightShiftManager.shared.previewColorTemperature(sender.floatValue / 100)
            refreshKelvinLabel()
        }
    }

    @IBAction func clickEnableSlider(_ sender: Any) {
        NightShiftManager.shared.isNightShiftEnabled = true
        
        let statusMenuController = (NSApplication.shared.delegate as! AppDelegate).statusMenu.delegate as! StatusMenuController
        statusMenuController.updateMenuItems()
        
        shiftSlider.isEnabled = true
        refreshKelvinLabel()
        Event.enableSlider.record()
        logw("Enable slider button clicked")
    }

    func refreshKelvinLabel() {
        let strength = Double(shiftSlider.floatValue / 100)
        // Approximation that maps menu slider strength to color temperature.
        let minKelvin = 3200.0
        let maxKelvin = 6500.0
        let kelvin = Int((maxKelvin - ((maxKelvin - minKelvin) * strength)).rounded())
        kelvinLabel.stringValue = "\(kelvin)K"
    }
}


class ScrollableSlider: NSSlider {
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }

        let range = maxValue - minValue
        var delta: CGFloat = 0.0

        //Allow horizontal scrolling on horizontal and circular sliders
        if self.isVertical && self.sliderType == .linear {
            delta = event.deltaY
        } else if self.userInterfaceLayoutDirection == .rightToLeft {
            delta = event.deltaY + event.deltaX
        } else {
            delta = event.deltaY - event.deltaX
        }

        //Account for natural scrolling
        if event.isDirectionInvertedFromDevice {
            delta *= -1
        }

        let increment = range * Double(delta) / 100
        var value = doubleValue + increment

        //Wrap around if slider is circular
        if sliderType == .circular {
            let minValue = self.minValue
            let maxValue = self.maxValue

            if value < minValue {
                value = maxValue - abs(increment)
            }
            if value > maxValue {
                value = minValue + abs(increment)
            }
        }

        self.doubleValue = value
        self.sendAction(action, to: target)
    }
}
