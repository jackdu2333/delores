//
//  SettingsView.swift
//  HuaciGongju
//

import SwiftUI

public class SettingsViewModel: ObservableObject {
    @Published public var selectedTab: Int = 0
    @Published public var isAccessibilityGranted: Bool = SelectionMonitor.isAccessibilityTrusted()

    // Add action sheet
    @Published public var showAddActionSheet: Bool = false
    @Published public var newActionTitle: String = ""
    @Published public var newActionIcon: String = "sparkles"
    @Published public var newActionPrompt: String = ""

    // Add profile sheet
    @Published public var showAddProfileSheet: Bool = false
    @Published public var newProfileName: String = ""
    @Published public var newProfileBaseUrl: String = "https://api.openai.com/v1"
    @Published public var newProfileApiKey: String = ""
    @Published public var newProfileModelName: String = ""

    public init() {}

    public func refreshAccessibility() {
        isAccessibilityGranted = SelectionMonitor.isAccessibilityTrusted()
    }
}

public struct SettingsView: View {
    @ObservedObject public var config = ConfigManager.shared
    @ObservedObject public var viewModel = SettingsViewModel()

    public init() {}

    public var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            ModelManagementView(config: config, viewModel: viewModel)
                .tabItem {
                    Label("大模型配置", systemImage: "cpu")
                }
                .tag(0)

            ActionManagementView(config: config, viewModel: viewModel)
                .tabItem {
                    Label("划词动作管理", systemImage: "sparkles")
                }
                .tag(1)

            GeneralSettingsView(config: config, viewModel: viewModel)
                .tabItem {
                    Label("通用设置", systemImage: "gearshape")
                }
                .tag(2)
        }
        .padding(20)
        .frame(width: 580, height: 500)
        .onAppear {
            viewModel.refreshAccessibility()
        }
    }
}

public struct ModelManagementView: View {
    @ObservedObject public var config: ConfigManager
    @ObservedObject public var viewModel: SettingsViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top active model selector
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("当前生效的默认模型：")
                        .font(.system(size: 13, weight: .bold))

                    Picker("", selection: $config.activeProfileId) {
                        ForEach(config.profiles) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)

                    Spacer()

                    Button(action: {
                        viewModel.showAddProfileSheet.toggle()
                    }) {
                        Label("添加新模型", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                HStack(spacing: 6) {
                    Text("正在使用: ")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(config.activeProfile.modelName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(" - ")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(config.activeProfile.baseUrl)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // Add Profile sheet / form
            if viewModel.showAddProfileSheet {
                VStack(alignment: .leading, spacing: 8) {
                    Text("添加自定义模型服务")
                        .font(.system(size: 12, weight: .bold))

                    HStack(spacing: 8) {
                        TextField("配置名称 (如: Qwen-Max)", text: $viewModel.newProfileName)
                            .textFieldStyle(.roundedBorder)
                        TextField("模型标识 (如: qwen-max)", text: $viewModel.newProfileModelName)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Base URL (如: https://dashscope.aliyuncs.com/compatible-mode/v1):", text: $viewModel.newProfileBaseUrl)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API Key:", text: $viewModel.newProfileApiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("保存") {
                            let name = viewModel.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let model = viewModel.newProfileModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty && !model.isEmpty else { return }

                            config.addProfile(
                                name: name,
                                baseUrl: viewModel.newProfileBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                                apiKey: viewModel.newProfileApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                modelName: model
                            )
                            viewModel.newProfileName = ""
                            viewModel.newProfileModelName = ""
                            viewModel.newProfileApiKey = ""
                            viewModel.showAddProfileSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.newProfileName.isEmpty || viewModel.newProfileModelName.isEmpty)

                        Button("取消") {
                            viewModel.showAddProfileSheet = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }

            // Profile List
            Text("已配置的模型服务商列表：")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            List {
                ForEach(0..<config.profiles.count, id: \.self) { idx in
                    let item = config.profiles[idx]
                    let isCurrent = (item.id == config.activeProfileId)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name)
                                .font(.system(size: 13, weight: .bold))

                            if isCurrent {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("当前默认")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                            } else {
                                Button("设为默认") {
                                    config.activeProfileId = item.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            Spacer()

                            if config.profiles.count > 1 && !isCurrent {
                                Button(action: {
                                    config.removeProfile(at: idx)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help("删除该配置")
                            }
                        }

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Base URL:")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("", text: Binding(
                                    get: { config.profiles[idx].baseUrl },
                                    set: { config.profiles[idx].baseUrl = $0 }
                                ))
                                .font(.system(size: 11))
                                .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Name:")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("", text: Binding(
                                    get: { config.profiles[idx].modelName },
                                    set: { config.profiles[idx].modelName = $0 }
                                ))
                                .font(.system(size: 11))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("API Key (本地免鉴权服务可填 local):")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            SecureField("", text: Binding(
                                get: { config.profiles[idx].apiKey },
                                set: { config.profiles[idx].apiKey = $0 }
                            ))
                            .font(.system(size: 11))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
    }
}

public struct ActionManagementView: View {
    @ObservedObject public var config = ConfigManager.shared
    @ObservedObject public var viewModel = SettingsViewModel()

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("划词动作管理")
                        .font(.system(size: 13, weight: .bold))
                    Text("自定义每个动作的 Prompt 约束或配置本地搜索")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: {
                    viewModel.showAddActionSheet.toggle()
                }) {
                    Label("添加自定义动作", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("恢复预设") {
                    config.resetToDefault()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.showAddActionSheet {
                VStack(alignment: .leading, spacing: 8) {
                    Text("新建动作")
                        .font(.system(size: 12, weight: .bold))

                    HStack(spacing: 8) {
                        TextField("动作名称 (如: 提炼待办)", text: $viewModel.newActionTitle)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        TextField("图标 (SF Symbol 如: list.bullet)", text: $viewModel.newActionIcon)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Spacer()

                        Button("保存") {
                            let title = viewModel.newActionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !title.isEmpty else { return }
                            config.addCustomAction(
                                title: title,
                                icon: viewModel.newActionIcon.trimmingCharacters(in: .whitespacesAndNewlines),
                                prompt: viewModel.newActionPrompt
                            )
                            viewModel.newActionTitle = ""
                            viewModel.newActionPrompt = ""
                            viewModel.showAddActionSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.newActionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("取消") {
                            viewModel.showAddActionSheet = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    TextEditor(text: $viewModel.newActionPrompt)
                        .font(.system(size: 11))
                        .frame(height: 50)
                        .padding(4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }

            List {
                ForEach(0..<config.actions.count, id: \.self) { index in
                    let item = config.actions[index]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { config.actions[index].isEnabled },
                                set: { config.actions[index].isEnabled = $0 }
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(.accentColor)
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))

                                    if item.isBuiltIn {
                                        Text("内置")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                    } else {
                                        Text("自定义")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.accentColor)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.12))
                                            .cornerRadius(4)
                                    }

                                    if item.type == .search {
                                        Text("浏览器搜索")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }
                            }

                            Spacer()

                            if !item.isBuiltIn {
                                Button(action: {
                                    config.removeAction(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help("删除自定义动作")
                            }
                        }

                        if item.type == .search {
                            TextField("搜索 URL 模板:", text: Binding(
                                get: { config.actions[index].searchTemplate },
                                set: { config.actions[index].searchTemplate = $0 }
                            ))
                            .font(.system(size: 11))
                            .textFieldStyle(.roundedBorder)
                        } else {
                            TextEditor(text: Binding(
                                get: { config.actions[index].prompt },
                                set: { config.actions[index].prompt = $0 }
                            ))
                            .font(.system(size: 11))
                            .frame(height: 48)
                            .padding(4)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)

                            // 该动作专属模型：留空表示跟随全局默认模型
                            HStack(spacing: 6) {
                                Text("使用模型")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Picker("", selection: Binding(
                                    get: { config.actions[index].preferredProfileId ?? "" },
                                    set: { config.actions[index].preferredProfileId = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("跟随全局默认").tag("")
                                    ForEach(config.profiles) { profile in
                                        Text(profile.name).tag(profile.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(maxWidth: 260)
                                .help("为该动作单独指定模型；选择「跟随全局默认」则使用模型管理中的当前默认模型")

                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
    }
}

public struct GeneralSettingsView: View {
    @ObservedObject public var config: ConfigManager
    @ObservedObject public var viewModel: SettingsViewModel

    public var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS 辅助功能权限")
                            .font(.system(size: 13, weight: .medium))
                        Text("划词助手需要辅助功能权限以捕获选中文本与光标位置")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if viewModel.isAccessibilityGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已授权")
                                .font(.system(size: 12))
                        }
                    } else {
                        Button("去授权") {
                            SelectionMonitor.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)

                Toggle("选中文本后自动呼出顶部瞬时控制器", isOn: $config.autoShowToolbar)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)

                Toggle("桌宠模式", isOn: $config.enableCompanionMode)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)

                Text("打开后，28pt 玻璃圆沿屏幕边缘巡逻，划词条与分屏岛从宠物朝里一侧长出。出厂关闭，仍是顶部瞬时控制器。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                Toggle("拖拽窗口唤出灵动分屏岛", isOn: $config.enableWindowSnapping)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
                    .disabled(config.enableCompanionMode)

                Text(config.enableCompanionMode
                     ? "由宠物接管。退出桌宠模式后按原开关恢复。"
                     : "拖动任意第三方窗口靠近屏幕顶部，即可唤出灵动分屏岛，快速吸附至二分屏(1/2)、主辅屏(2:1)、四等分(1/4田字格)或三等分(1/3)。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                Toggle("开启分屏中缝联动调节", isOn: $config.enableSplitDivider)
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
                    .disabled(config.enableCompanionMode)

                Text(config.enableCompanionMode
                     ? "由宠物接管。退出桌宠模式后按原开关恢复。"
                     : "当两窗口左右贴合分屏时，悬停中缝可拖动联动调节宽度，双击中缝快速复位 50%:50% 平分。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            } header: {
                Text("系统权限与呼出行为")
                    .font(.system(size: 12, weight: .bold))
            }

            Section {
                Toggle("记录明文调试日志 (含选中文本与大模型对话)", isOn: $config.enablePlaintextLogging)
                    .font(.system(size: 13))

                Text("默认关闭以保护隐私。开启时会完整记录选中文本与对话内容；关闭时仅记录请求统计与掩码信息。\n日志安全存储于 ~/Library/Logs/HuaciGongju/")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack {
                    Spacer()
                    Button("打开日志文件夹") {
                        NSWorkspace.shared.open(ChatLog.logDirectoryURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("隐私与调试日志")
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .formStyle(.grouped)
    }
}

