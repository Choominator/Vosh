import Access
import Input

/// Interface between the user and the ``Access`` framework.
@MainActor final class VoshAgent {
    /// ``Access`` framework handle.
    private let access: Access

    /// Creates the user agent.
    init?() async {
        guard let access = await Access() else {
            return nil
        }
        await access.setTimeout(seconds: 5.0)
        self.access = access
        Input.shared.bindKey(key: .keyboardTab, action: {[weak self] in await self?.access.readFocus()})
        Input.shared.bindKey(key: .keyboardLeftArrow, action: {[weak self] in await self?.access.focusNextSibling(backwards: true)})
        Input.shared.bindKey(key: .keyboardRightArrow, action: {[weak self] in await self?.access.focusNextSibling(backwards: false)})
        Input.shared.bindKey(key: .keyboardDownArrow, action: {[weak self] in await self?.access.focusFirstChild()})
        Input.shared.bindKey(key: .keyboardUpArrow, action: {[weak self] in await self?.access.focusParent()})
        Input.shared.bindKey(key: .keyboardSlashAndQuestion, action: {[weak self] in await self?.access.dumpApplication()})
        Input.shared.bindKey(key: .keyboardPeriodAndRightAngle, action: {[weak self] in await self?.access.dumpApplication()})
        Input.shared.bindKey(key: .keyboardCommaAndLeftAngle, action: {[weak self] in await self?.access.dumpFocus()})
    }
}
