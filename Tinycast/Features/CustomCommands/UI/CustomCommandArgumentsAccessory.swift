import SwiftUI

/// Connects the current Tinycast command model to Delores' existing inline argument fields.
@MainActor
enum CustomCommandArgumentsAccessory {
    static func make(
        command: CustomCommand?, vm: PaletteState, metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding, onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let command, !command.arguments.isEmpty else { return nil }
        let arguments = command.arguments.indices.map { index in
            QuicklinkTemplateEngine.MissingArgument(
                name: "\(CustomCommandArgument.fieldID(at: index)) · \(command.arguments[index].name)",
                options: [])
        }
        let fields = Dictionary(uniqueKeysWithValues: arguments.enumerated().map {
            ($0.element.name, CustomCommandArgument.fieldID(at: $0.offset))
        })
        let value = { (name: String) in
            binding(command: command, field: fields[name] ?? name, vm: vm)
        }
        let firstOwed = command.arguments.indices.first {
            !command.arguments[$0].isOptional
                && value(arguments[$0].name).wrappedValue.isEmpty
        }.map { arguments[$0].name }
        return PaletteHeaderAccessory(
            width: QuicklinkArgumentsRow.totalWidth(
                for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.name), firstIncompleteField: firstOwed,
            placement: .afterQuery,
            view: AnyView(
                QuicklinkArgumentsRow(
                    arguments: arguments, symbol: command.symbol, value: value, focused: focus,
                    openOptions: { _ in },
                    onSubmit: {
                        guard let firstOwed else { return onSubmit() }
                        focus.wrappedValue = firstOwed
                    }
                )
                .id(command.entryID)))
    }

    static func values(for command: CustomCommand, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for index in command.arguments.indices {
            let field = CustomCommandArgument.fieldID(at: index)
            let typed = vm.commandArguments[PaletteState.argumentKey(command.entryID, field)] ?? ""
            if !typed.isEmpty { values[field] = typed }
        }
        return values
    }

    private static func binding(
        command: CustomCommand, field: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(command.entryID, field)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }
}
