//
//  TextInputSetting.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit

class TextInputSetting: NSObject, Setting, /*KeyboardAvoidanceSetting,*/ UITextFieldDelegate {
    
    var section: SettingSection?
    var usesClosures: Bool
    
    private let titleClosure: () -> String
    private let initialTextFieldText: String?
    private let textFieldTextClosure: (() -> String?)?
    private let textFieldPlaceholderClosure: () -> String?
    private let keyboardType: UIKeyboardType
    private let textBehindTextField: String?
    private let textFieldValueAction: ((String?, Setting) -> Void)?
    
    public var registerForKeyboardAvoidanceClosure: ((UITableViewCell) -> Void)?
    
    fileprivate lazy var textField: UITextField = {
        let textField = UITextField()
        textField.backgroundColor = .clear
        textField.textColor = .stone
        textField.placeholder = self.textFieldPlaceholderClosure()
        textField.text = self.initialTextFieldText ?? self.textFieldTextClosure?()
        textField.layer.cornerRadius = 10
        textField.delegate = self
        textField.keyboardType = self.keyboardType
        textField.textAlignment = .right
        textField.clipsToBounds = true
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 150),
            textField.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // textField.addDoneToolbar()
        
        return textField
    }()
    
    fileprivate lazy var titleLabel = UILabel(/*text: self.titleClosure(), font: .preferredFont(forTextStyle: .body)*/)
    
    fileprivate lazy var behindLabel = UILabel(/*text: self.textBehindTextField, textColor: .secondaryColor, font: .preferredFont(forTextStyle: .body)*/)
    
    fileprivate lazy var internalTableViewCell: UITableViewCell = {
        let cell = UITableViewCell()
        cell.backgroundColor = .parchment
        cell.accessoryType = .none
        cell.selectionStyle = .none

        let safeArea = cell.contentView.layoutMarginsGuide

        titleLabel.adjustsFontForContentSizeCategory = true
        
        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(self.textField)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.textField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            self.textField.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            self.textField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])

        if self.textBehindTextField == nil {
            self.textField.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor).isActive = true
        } else {
            behindLabel.adjustsFontForContentSizeCategory = true
            cell.contentView.addSubview(behindLabel)
            behindLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                behindLabel.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
                behindLabel.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
                behindLabel.leadingAnchor.constraint(equalTo: self.textField.trailingAnchor, constant: 10)
            ])
        }
        
        return cell
    }()
    
    init(title: @escaping () -> String, initialTextFieldText: String? = nil, textFieldText: (() -> String?)? = nil, textFieldPlaceholder: @escaping () -> String? = { return nil }, keyboardType: UIKeyboardType = .default, textBehindTextField: String? = nil, textFieldValueAction: ((String?, Setting) -> Void)? = nil) {
        self.titleClosure = title
        self.initialTextFieldText = initialTextFieldText
        self.textFieldTextClosure = textFieldText
        self.textFieldPlaceholderClosure = textFieldPlaceholder
        self.keyboardType = keyboardType
        self.textBehindTextField = textBehindTextField
        self.textFieldValueAction = textFieldValueAction
        self.usesClosures = true
    }
    
    convenience init(title: String, textFieldText: String? = nil, textFieldPlaceholder: String? = nil, keyboardType: UIKeyboardType = .default, textBehindTextField: String? = nil, textFieldValueAction: ((String?, Setting) -> Void)? = nil) {
        self.init(title: { return title }, initialTextFieldText: textFieldText, textFieldPlaceholder: { return textFieldPlaceholder }, keyboardType: keyboardType, textBehindTextField: textBehindTextField, textFieldValueAction: textFieldValueAction)
        self.usesClosures = false
    }
    
    var tableViewCell: UITableViewCell {
        get {
            return internalTableViewCell
        }
    }
    
    func runSelectAction(controller: UIViewController) {
        textField.becomeFirstResponder()
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        registerForKeyboardAvoidanceClosure?(self.tableViewCell)
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        if let textFieldShouldReturnAction = textFieldValueAction {
            textFieldShouldReturnAction(textField.text, self)
        }
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.endEditing(true)
    }
    
    func updateClosures() {
        if self.usesClosures {
            DispatchQueue.main.async {
                self.titleLabel.text = self.titleClosure()
                self.textField.placeholder = self.textFieldPlaceholderClosure()
                if let textFieldClosure = self.textFieldTextClosure {
                    self.textField.text = textFieldClosure()
                }
            }
        }
    }
    
}
