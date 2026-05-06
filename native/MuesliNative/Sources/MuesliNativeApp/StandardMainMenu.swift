import AppKit

enum StandardMainMenu {
    static func build(appName: String) -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: appName)
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        addCommand(title: "Undo", action: Selector(("undo:")), key: "z", to: editMenu)
        addCommand(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        addCommand(title: "Cut", action: #selector(NSText.cut(_:)), key: "x", to: editMenu)
        addCommand(title: "Copy", action: #selector(NSText.copy(_:)), key: "c", to: editMenu)
        addCommand(title: "Paste", action: #selector(NSText.paste(_:)), key: "v", to: editMenu)
        addCommand(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: editMenu)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        addCommand(title: "Close", action: #selector(NSWindow.performClose(_:)), key: "w", to: windowMenu)
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }

    private static func addCommand(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
