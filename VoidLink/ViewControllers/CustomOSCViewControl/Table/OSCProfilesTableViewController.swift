//
//  OSCProfilesTableViewController.m -> OSCProfilesTableViewController.swift
//  Moonlight
//
//  Created by Long Le on 11/28/22.
//  Copyright © 2022 Moonlight Game Streaming Project. All rights reserved.
//
//  Modified by True砖家 since 2024.6.24
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

import UIKit

final class ProfileTableViewCell: UITableViewCell {
    @IBOutlet weak var name: UILabel!
}

@objc(FileOperation)
enum FileOperation: Int {
    case importOperation = 0
    case exportOperation = 1
}

@objc enum OSCProfilesTableViewLoadingMode: Int {
    case selectProfile  
    case selectProfileFromStreamView
    case selectProfileFromMainFrame
    case pickProfile
    case pickProfileData
}

@objcMembers
final class OSCProfilesTableViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate, UIGestureRecognizerDelegate, ControllerUINavigationDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var profileTableViewNavigationBar: UINavigationBar!
    @IBOutlet private weak var profileTableViewNavigationItem: UINavigationItem!

    var currentFileOperation: FileOperation = .importOperation
    var needToUpdateOscLayoutTVC: (() -> Void)?
    var loadingMode: OSCProfilesTableViewLoadingMode = .selectProfile
    @nonobjc var pickedProfileDataHandler: ((OSCProfile) -> Void)?
    weak var currentOSCButtonLayers: NSMutableSet?
    var layoutViewBounds: CGRect = .zero

    private var profilesManager: OSCProfilesManager!
    private var horizontalConstraintsConfigured = false
    private var profiles: NSMutableArray = []
    private var selectedProfileIndex = 0
    private var profilesLoadGeneration = 0

    private func contentWidthMultiplier() -> CGFloat {
        PublicUtils.viewIsLandscape(view) ? (PublicUtils.isIPhone ? 0.8 : 0.65) : (PublicUtils.isIPhone ? 0.83 : 0.85)
    }

    private func updateHorizontalLayoutConstraints() {
        let horizontalConstraints = view.constraints.filter { constraint in
            let firstItem = constraint.firstItem as? UIView
            let secondItem = constraint.secondItem as? UIView
            let involvesManagedView = firstItem == tableView ||
                firstItem == profileTableViewNavigationBar ||
                secondItem == tableView ||
                secondItem == profileTableViewNavigationBar
            let isHorizontalConstraint: Bool = {
                switch (constraint.firstAttribute, constraint.secondAttribute) {
                case (.leading, _), (.trailing, _), (.left, _), (.right, _), (.width, _), (.centerX, _),
                     (_, .leading), (_, .trailing), (_, .left), (_, .right), (_, .width), (_, .centerX):
                    return true
                default:
                    return false
                }
            }()

            return involvesManagedView && isHorizontalConstraint
        }

        NSLayoutConstraint.deactivate(horizontalConstraints)

        [tableView, profileTableViewNavigationBar].forEach { controlledView in
            controlledView?.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            profileTableViewNavigationBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            profileTableViewNavigationBar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: contentWidthMultiplier()),
            tableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: contentWidthMultiplier()),
        ])
    }

    private func getCurrentOrientation() -> UIInterfaceOrientationMask {
        let bounds = UIScreen.main.bounds
        if bounds.width > bounds.height {
            return .landscape
        } else {
            return [.portrait, .portraitUpsideDown]
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        getCurrentOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.post(name: Notification.Name("OscLayoutTableViewCloseNotification"), object: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if #available(iOS 13.0, *) {
            ControllerNavigator.restorePreviousUINavigationDelegate(ifCurrentDelegateIs: self)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        profileTableViewNavigationBar.layer.cornerRadius = 15
        profileTableViewNavigationBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        profileTableViewNavigationBar.layer.masksToBounds = true

        tableView.layer.cornerRadius = 15
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.layer.masksToBounds = true

        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)

        if PublicUtils.liquidGlassEnabled {
            tableView.separatorColor = UIColor.white.withAlphaComponent(PublicUtils.isIPhone ? 0.28 : 0.165)
        } else {
            tableView.separatorColor = UIColor.white.withAlphaComponent(0.3)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        profilesManager = OSCProfilesManager.sharedManager(layoutViewBounds)
        configureTableView()
        updateHorizontalLayoutConstraints()
        horizontalConstraintsConfigured = true
        tableView.alpha = 1
        tableView.backgroundColor = UIColor.black.withAlphaComponent(self.loadingMode == .selectProfileFromMainFrame ? (
            ThemeManager.userInterfaceStyle() == .dark ? 0.83 : 0.6
        ) : 0.43)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        if PublicUtils.liquidGlassEnabled, #available(iOS 26.0, *) {
            profileTableViewNavigationItem.leftBarButtonItems?.forEach { $0.hidesSharedBackground = true }
            profileTableViewNavigationItem.rightBarButtonItems?.forEach { $0.hidesSharedBackground = true }
        }

        reloadProfilesAsync(scrollToSelected: true)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.updateHorizontalLayoutConstraints()
            self.view.layoutIfNeeded()
        })
    }

    @objc private func dismissSelf() {
        dismiss(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !horizontalConstraintsConfigured {
            updateHorizontalLayoutConstraints()
            horizontalConstraintsConfigured = true
        }
        configureTableView()
        if profiles.count > 0 {
            scrollToSelectedProfile(animated: true)
        } else {
            reloadProfilesAsync(scrollToSelected: true)
        }
        
        if (loadingMode == .selectProfileFromMainFrame || loadingMode == .selectProfileFromStreamView)
            && ControllerUtil.primaryGCController != nil {
            if #available(iOS 13.0, *) {
                ControllerNavigator.setUINavigationDelegate(self)
            }
        }
    }

    private func configureTableView() {
        tableView.tableHeaderView = UIView(frame: .zero)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UINib(nibName: "ProfileTableViewCell", bundle: nil), forCellReuseIdentifier: "Cell")
    }

    private func reloadProfilesAsync(scrollToSelected: Bool = false, notify: Bool = false) {
        profilesLoadGeneration += 1
        let generation = profilesLoadGeneration
        let manager = profilesManager

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let manager else { return }

            let loadedProfiles = manager.getAllProfiles()
            let loadedSelectedIndex = Self.selectedProfileIndex(in: loadedProfiles)

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.profilesLoadGeneration else { return }

                self.profiles = loadedProfiles
                self.selectedProfileIndex = loadedSelectedIndex
                self.tableView.reloadData()

                if scrollToSelected {
                    self.scrollToSelectedProfile(animated: true)
                }

                if notify {
                    self.notifyProfileViewDidRefresh()
                }
            }
        }
    }

    private func scrollToSelectedProfile(animated: Bool) {
        guard let selectedProfileIndex = validProfileIndex(selectedProfileIndex) else {
            return
        }

        let indexPath = IndexPath(row: selectedProfileIndex, section: 0)
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
    }

    private func moveSelectedProfile(by offset: Int) {
        PublicUtils.runOnMain { [weak self] in
            guard let self,
                  self.profiles.count > 0,
                  self.tableView.numberOfSections > 0,
                  self.tableView.numberOfRows(inSection: 0) > 0 else {
                return
            }

            let maxIndex = min(self.profiles.count, self.tableView.numberOfRows(inSection: 0)) - 1
            let currentIndex = min(max(self.selectedProfileIndex, 0), maxIndex)
            let nextIndex = min(max(currentIndex + offset, 0), maxIndex)
            let nextIndexPath = IndexPath(row: nextIndex, section: 0)

            self.tableView.selectRow(at: nextIndexPath, animated: true, scrollPosition: .middle)
            self.tableView(self.tableView, didSelectRowAt: nextIndexPath)
        }
    }

    private func validProfileIndex(_ index: Int) -> Int? {
        guard profiles.count > 0 else { return nil }
        return min(max(index, 0), profiles.count - 1)
    }

    private func notifyProfileViewDidRefresh() {
        needToUpdateOscLayoutTVC?()
        if loadingMode != .selectProfileFromStreamView
            && loadingMode != .pickProfile
            && loadingMode != .pickProfileData
            && loadingMode != .selectProfile
        {
            guard let selectedProfileIndex = validProfileIndex(selectedProfileIndex) else { return }
            NotificationCenter.default.post(name: Notification.Name("GameProfileSelectedNotification"), object: self.profiles[selectedProfileIndex])
        }
    }

    private static func selectedProfileIndex(in profiles: NSMutableArray) -> Int {
        for index in 0..<profiles.count {
            guard let profile = profiles.object(at: index) as? OSCProfile else {
                continue
            }

            if profile.isSelected {
                return index
            }
        }

        return 0
    }

    @IBAction func duplicateTapped(_ sender: Any?) {
        let inputAlert = UIAlertController(
            title: LocalizationHelper.localizedString(forKey: "Enter the name you want to save this profile as"),
            message: "",
            preferredStyle: .alert
        )
        inputAlert.addTextField { textField in
            textField.placeholder = LocalizationHelper.localizedString(forKey: "name")
            if #available(iOS 13.0, *) {
                // textField.textColor = .label
            }
            textField.clearButtonMode = .whileEditing
            textField.borderStyle = .none
        }
        inputAlert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Cancel"), style: .default) { _ in
            inputAlert.dismiss(animated: false)
        })
        inputAlert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Save"), style: .default) { [weak self] _ in
            guard let self else { return }
            let enteredProfileName = inputAlert.textFields?.first?.text ?? ""

            if enteredProfileName == "Default" {
                let alert = UIAlertController(
                    title: "",
                    message: LocalizationHelper.localizedString(forKey: "Saving over the 'Default' profile is not allowed"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Ok"), style: .default) { _ in
                    alert.dismiss(animated: false) {
                        self.present(inputAlert, animated: true)
                    }
                })
                self.present(alert, animated: true)
            } else if enteredProfileName.isEmpty {
                let alert = UIAlertController(
                    title: "",
                    message: LocalizationHelper.localizedString(forKey: "Profile name cannot be blank!"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Ok"), style: .default) { _ in
                    alert.dismiss(animated: false) {
                        self.present(inputAlert, animated: true)
                    }
                })
                self.present(alert, animated: true)
            } else if self.profilesManager.profileNameAlreadyExist(enteredProfileName) {
                let alert = UIAlertController(
                    title: "",
                    message: LocalizationHelper.localizedString(forKey: "Profile name already exists"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Ok"), style: .default))
                self.present(alert, animated: true)
            } else {
                self.profilesManager.duplicateSelectedProfile(withName: enteredProfileName)
                let alert = UIAlertController(
                    title: "",
                    message: LocalizationHelper.localizedString(forKey: "Profile %@ duplicated from current layout", enteredProfileName),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Ok"), style: .default) { _ in
                    alert.dismiss(animated: false)
                    self.profileViewRefresh()
                })
                self.present(alert, animated: true)
            }
        })

        present(inputAlert, animated: true)
    }

    func profileViewRefresh() {
        reloadProfilesAsync(notify: true)
    }

    @IBAction func deleteTapped(_ sender: Any?) {
        profilesManager.deleteCurrentSelectedProfile()
        profileViewRefresh()
    }

    @IBAction func exportDataTapped(_ sender: Any?) {
        currentFileOperation = .exportOperation
        let tempPath = NSTemporaryDirectory().appending("profiles.bin")
        try? Data().write(to: URL(fileURLWithPath: tempPath), options: .atomic)

        let picker = UIDocumentPickerViewController(url: URL(fileURLWithPath: tempPath), in: .exportToService)
        picker.delegate = self
        present(picker, animated: true)
    }

    @IBAction func importDataTapped(_ sender: Any?) {
        currentFileOperation = .importOperation
        let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @IBAction func restoreTapped(_ sender: Any?) {
        profilesManager.importDefaultTemplates()
        profileViewRefresh()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        switch currentFileOperation {
        case .exportOperation:
            profilesToFile(url)
        case .importOperation:
            fileToProfiles(url)
        }
    }

    private func profilesToFile(_ destinationURL: URL) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: profilesManager.getEncodedProfiles(), requiringSecureCoding: true)
            let accessed = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            // NSLog("写入失败: \(error)")
        }
    }

    private func fileToProfiles(_ sourceURL: URL) {
        var restoreFailed = false
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        if !accessed {
            restoreFailed = true
        }

        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileData = try Data(contentsOf: sourceURL)
            // NSLog("profile file read: \(UInt32(fileData.count))")
            let classes: [AnyClass] = [NSMutableData.self, NSMutableArray.self]
            let profilesEncoded = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: fileData) as? NSMutableArray

            let restoredAlert = UIAlertController(
                title: LocalizationHelper.localizedString(forKey: ""),
                message: LocalizationHelper.localizedString(forKey: "Pofiles imported"),
                preferredStyle: .alert
            )
            let failedAlert = UIAlertController(
                title: LocalizationHelper.localizedString(forKey: ""),
                message: LocalizationHelper.localizedString(forKey: "Failed to import profiles"),
                preferredStyle: .alert
            )
            let okAction = UIAlertAction(title: LocalizationHelper.localizedString(forKey: "OK"), style: .default)

            if restoreFailed || profilesEncoded == nil {
                failedAlert.addAction(okAction)
                present(failedAlert, animated: true)
            } else {
                profilesManager.importEncodedProfiles(profilesEncoded!)
                restoredAlert.addAction(okAction)
                present(restoredAlert, animated: true)
            }

            profileViewRefresh()
            // NSLog("profile test: \(UInt32(profilesEncoded?.count ?? 0))")
        } catch {
            restoreFailed = true
            let failedAlert = UIAlertController(
                title: LocalizationHelper.localizedString(forKey: ""),
                message: LocalizationHelper.localizedString(forKey: "Failed to import profiles"),
                preferredStyle: .alert
            )
            failedAlert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "OK"), style: .default))
            present(failedAlert, animated: true)
            profileViewRefresh()
            // NSLog("解码失败: \(error)")
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        profiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as? ProfileTableViewCell,
              indexPath.row < profiles.count,
              let profile = profiles.object(at: indexPath.row) as? OSCProfile,
              let nameLabel = cell.name else {
            return UITableViewCell()
        }

        nameLabel.text = profile.name.localizedProfileName
        nameLabel.backgroundColor = UIColor.clear
        nameLabel.alpha = 1.0
        nameLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        nameLabel.font = UIFont.systemFont(ofSize: 18.5, weight: .medium)
        nameLabel.shadowColor = UIColor.black
        nameLabel.shadowOffset = CGSize(width: 0.5, height: 0.5)

        cell.backgroundColor = UIColor.clear
        cell.contentView.backgroundColor = UIColor.clear

        if loadingMode != .pickProfileData,
           indexPath.row == selectedProfileIndex {
            cell.accessoryType = UITableViewCell.AccessoryType.checkmark
            let checkmarkLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
            checkmarkLabel.text = "✓"
            checkmarkLabel.font = .systemFont(ofSize: 25)
            checkmarkLabel.textAlignment = .center
            checkmarkLabel.textColor = .green
            checkmarkLabel.layer.zPosition = 0
            cell.accessoryView = checkmarkLabel
        } else {
            cell.accessoryType = UITableViewCell.AccessoryType.none
            cell.accessoryView = nil
        }

        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        60.0
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard indexPath.row < profiles.count else { return }

        if let profile = profiles.object(at: indexPath.row) as? OSCProfile, profile.name == "Default" {
            let alert = UIAlertController(title: "", message: "Deleting the 'Default' profile is not allowed", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Ok"), style: .default) { _ in
                alert.dismiss(animated: false)
            })
            present(alert, animated: true)
            return
        }

        if editingStyle == .delete {
            if let profile = profiles.object(at: indexPath.row) as? OSCProfile, profile.isSelected, indexPath.row > 0,
               let previousProfile = profiles.object(at: indexPath.row - 1) as? OSCProfile {
                previousProfile.isSelected = true
            }

            profiles.removeObject(at: indexPath.row)

            let profilesEncoded = NSMutableArray()
            for case let profileDecoded as OSCProfile in profiles {
                if let profileEncoded = try? NSKeyedArchiver.archivedData(withRootObject: profileDecoded, requiringSecureCoding: true) {
                    profilesEncoded.add(profileEncoded)
                }
            }
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: profilesEncoded, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "OSCProfiles")
                UserDefaults.standard.synchronize()
            }

            reloadProfilesAsync()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0,
              indexPath.row >= 0,
              indexPath.row < profiles.count else {
            return
        }

        if loadingMode == .pickProfileData,
           let pickedProfile = profiles.object(at: indexPath.row) as? OSCProfile {
            pickedProfileDataHandler?(pickedProfile)
            dismiss(animated: false)
            return
        }

        let selectedIndexPath = IndexPath(row: indexPath.row, section: 0)
        let lastSelectedIndex = validProfileIndex(selectedProfileIndex)
        let lastSelectedIndexPath = lastSelectedIndex.map { IndexPath(row: $0, section: 0) }

        if selectedIndexPath != lastSelectedIndexPath {
            if let lastSelectedIndexPath {
                let previousCell = tableView.cellForRow(at: lastSelectedIndexPath)
                previousCell?.accessoryType = .none
                previousCell?.accessoryView = nil
            }

            profilesManager.setProfileToSelected(UInt32(indexPath.row))
            selectedProfileIndex = indexPath.row

            let selectedCell = tableView.cellForRow(at: selectedIndexPath)
            selectedCell?.accessoryType = .checkmark
            let checkmarkLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
            checkmarkLabel.text = "✓"
            checkmarkLabel.font = .systemFont(ofSize: 25)
            checkmarkLabel.textAlignment = .center
            checkmarkLabel.textColor = .green
            checkmarkLabel.layer.zPosition = 0
            selectedCell?.accessoryView = checkmarkLabel

            let rowsToReload = [lastSelectedIndexPath, selectedIndexPath]
                .compactMap { $0 }
                .filter {
                    $0.section < tableView.numberOfSections &&
                    $0.row >= 0 &&
                    $0.row < tableView.numberOfRows(inSection: $0.section)
                }
            if !rowsToReload.isEmpty {
                tableView.reloadRows(at: rowsToReload, with: .none)
            }
        }
        profileViewRefresh()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if (loadingMode != .selectProfile
            && loadingMode != .selectProfileFromMainFrame
            && loadingMode != .selectProfileFromStreamView
            ),
           let touchView = touch.view,
           touchView.isDescendant(of: tableView) {
            return true
        }
        return touch.view == view
    }
    
    @available(iOS 13.0, *)
    func getNavigationElements() -> [ControllerNavigationElement] {
        var elements: [ControllerNavigationElement] = []
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .y, action: "previousItem"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadDown : .a, action: "nextItem"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .x, action: "exit"))
        return elements
    }
    
    func navigateByController(forward: Bool) {
    }
    
    func navigateByController(downward: Bool) {
        
    }

    func persistControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {}
    
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement) {
    }
    
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {
        guard pressed else { return }
        PublicUtils.runOnMain { [weak self] in
            switch navigation.action {
            case "previousItem":
                self?.moveSelectedProfile(by: -1)
            case "nextItem":
                self?.moveSelectedProfile(by: 1)
            case "exit":
                self?.dismiss(animated: false)
            default:
                break
            }
        }
    }
}
