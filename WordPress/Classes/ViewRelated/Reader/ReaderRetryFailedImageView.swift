//
//  ReaderRetryFailedImageView.swift
//  WordPress
//
//  Created by Paul Von Schrottky on 10/5/19.
//  Copyright © 2019 WordPress. All rights reserved.
//

import UIKit
import Gridicons

protocol ReaderRetryFailedImageDelegate: AnyObject {
    func didTapRetry()
}

fileprivate class LinkTextView: UITextView {
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        return []
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        return CGRect.zero.offsetBy(dx: .greatestFiniteMagnitude, dy: .greatestFiniteMagnitude)
    }
}

class ReaderRetryFailedImageView: UIView {

    @IBOutlet weak private var imageView: UIImageView! {
        didSet {
            let iconImage = Gridicon.iconOfType(.imageRemove)
            let imageView = UIImageView(image: iconImage.withRenderingMode(.alwaysTemplate))
            imageView.tintColor = UIColor.textSubtle
        }
    }

    @IBOutlet weak private var textView: LinkTextView! {
        didSet {
            textView.textDragInteraction?.isEnabled = false
            textView.adjustsFontForContentSizeCategory = true
        }
    }

    private let attributedString: NSAttributedString = {
        let mutableAttributedString = NSMutableAttributedString()

        let textLocalizedString = NSLocalizedString("Image not loaded.", comment: "Message displayed in image area when a site image fails to load.")
        mutableAttributedString.append(NSAttributedString(string: textLocalizedString, attributes: WPStyleGuide.readerDetailAttributesForRetryText()))

        let singleSpaceString = " "
        mutableAttributedString.append(NSAttributedString(string: singleSpaceString))

        let buttonLocalizedString = NSLocalizedString("Retry", comment: "Retry button title in image area when a site image fails to load.")
        mutableAttributedString.append(NSAttributedString(string: buttonLocalizedString, attributes: WPStyleGuide.readerDetailAttributesForRetryButton()))

        return mutableAttributedString
    }()

    weak var delegate: ReaderRetryFailedImageDelegate?

    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .retryBackground
        textView.attributedText = attributedString
    }
}

extension ReaderRetryFailedImageView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard interaction == .invokeDefaultAction, URL.scheme == "tap" else {
            return false
        }
        delegate?.didTapRetry()
        return false
    }
}
