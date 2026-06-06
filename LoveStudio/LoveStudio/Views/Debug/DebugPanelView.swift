import SwiftUI
import AppKit

struct DebugPanelView: View {
    let debugServer  : DebugServer
    let breakpoints  : BreakpointManager
    let isDebugging  : Bool
    var onJump       : ((String, Int) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            callStackPanel
                .frame(width: 210)

            Divider()

            VariablesPanel(
                variables: debugServer.localVars,
                debugServer: debugServer,
                isPaused: debugServer.isPaused
            )
            .frame(maxWidth: .infinity)

            Divider()

            breakpointsPanel
                .frame(width: 190)
        }
    }

    // MARK: Call Stack

    private var callStackPanel: some View {
        Group {
            if debugServer.callStack.isEmpty {
                placeholder(isDebugging ? "Running…" : "Not debugging")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(debugServer.callStack) { frame in
                            CallStackRow(frame: frame) {
                                onJump?(frame.file, frame.line)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: Breakpoints

    private var breakpointsPanel: some View {
        Group {
            if breakpoints.all.isEmpty {
                placeholder("Click line numbers\nto add breakpoints")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(breakpoints.all) { bp in
                            BreakpointRow(breakpoint: bp,
                                          onRemove: { breakpoints.remove(file: bp.file, line: bp.line) },
                                          onTap: { onJump?(bp.file, bp.line) })
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Variables Panel

struct VariablesPanel: View {
    let variables  : [DebugVariable]
    let debugServer: DebugServer
    let isPaused   : Bool

    @State private var expanded: Set<UUID>             = []
    @State private var children: [UUID: [DebugVariable]] = [:]
    @State private var loading: Set<UUID>              = []

    var body: some View {
        if variables.isEmpty {
            Text(isPaused ? "No variables" : "")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["local", "upvalue", "global"], id: \.self) { scope in
                        let group = variables.filter { $0.scope == scope }
                        if !group.isEmpty {
                            sectionHeader(scope)
                            ForEach(group) { variable in
                                variableRow(variable, depth: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ scope: String) -> some View {
        Text(scope.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func variableRow(_ variable: DebugVariable, depth: Int) -> AnyView {
        let isTable    = variable.type == "table"
        let isExpanded = expanded.contains(variable.id)
        let isLoading  = loading.contains(variable.id)
        let kids       = children[variable.id] ?? []

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                if depth > 0 { Color.clear.frame(width: CGFloat(depth) * 14) }

                if isTable {
                    Button { toggleExpand(variable) } label: {
                        Group {
                            if isLoading {
                                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                            } else {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16)
                }

                Text(variable.name)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(scopeColor(variable.scope))
                    .frame(width: max(60, 90 - CGFloat(depth) * 14), alignment: .leading)
                    .lineLimit(1)

                Text(variable.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isTable ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(variable.type)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(isExpanded ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { if isTable { toggleExpand(variable) } }

            Divider().opacity(0.25)
                .padding(.leading, depth > 0 ? CGFloat(depth) * 14 + 10 : 10)

            if isExpanded {
                if kids.isEmpty && !isLoading {
                    HStack {
                        Color.clear.frame(width: CGFloat(depth + 1) * 14 + 28)
                        Text("(empty table)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.2)
                } else {
                    ForEach(kids) { child in
                        variableRow(child, depth: depth + 1)
                    }
                }
            }
        })
    }

    private func toggleExpand(_ variable: DebugVariable) {
        if expanded.contains(variable.id) {
            expanded.remove(variable.id)
        } else {
            expanded.insert(variable.id)
            if children[variable.id] == nil { fetchChildren(of: variable) }
        }
    }

    private func fetchChildren(of variable: DebugVariable) {
        loading.insert(variable.id)
        let key = variable.tableKey
        guard !key.isEmpty else {
            children[variable.id] = []
            loading.remove(variable.id)
            return
        }
        let expression = DebugValueInspector.childrenExpression(forTableKey: key)
        debugServer.evaluate(expression) { result in
            let kids = DebugValueInspector.parseChildren(result)
            DispatchQueue.main.async {
                self.children[variable.id] = kids
                self.loading.remove(variable.id)
            }
        }
    }

    private func scopeColor(_ scope: String) -> Color {
        switch scope {
        case "local":   return Color(nsColor: .systemPurple)
        case "upvalue": return Color(nsColor: .systemBlue)
        case "global":  return Color(nsColor: .systemOrange)
        default:        return Color(nsColor: .systemGray)
        }
    }
}

// MARK: - Call Stack Row

private struct CallStackRow: View {
    let frame: DebugStackFrame
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(frame.functionName.isEmpty ? "(anonymous)" : frame.functionName)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
            Text("\(frame.file):\(frame.line)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Breakpoint Row

private struct BreakpointRow: View {
    let breakpoint: Breakpoint
    let onRemove: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Text("\(breakpoint.file):\(breakpoint.line)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Debug Value Inspector

enum DebugValueInspector {
    static func childrenExpression(forTableKey key: String) -> String {
        "(function() if type(_LuaAppReg)~='table' then return 'NO_REG' end; local t=_LuaAppReg[\"\(key)\"]; if type(t)~='table' then return 'NO_KEY' end; local r,c,seen={},0,{}; local function push(name,v) if c>=96 then return end; local tv=type(v); local sv=tostring(v); if #sv>60 then sv=sv:sub(1,57)..'...' end; local tk=''; if tv=='table' then _LuaAppRegN=(_LuaAppRegN or 0)+1; tk=tostring(_LuaAppRegN); _LuaAppReg[tk]=v end; r[#r+1]=string.format('{name=%q,value=%q,type=%q,scope=%q,tkey=%q}',tostring(name),sv,tv,'field',tk); c=c+1 end; for i=1,#t do if rawget(t,i) ~= nil then seen[i]=true; push(i,t[i]) end end; for k,v in pairs(t) do if not seen[k] then push(k,v) end end; local mt=getmetatable(t); if mt then push('[metatable]', mt) end; return '{'..table.concat(r,',')..'}' end)()"
    }

    static func parseChildren(_ raw: String) -> [DebugVariable] {
        var variables: [DebugVariable] = []
        guard let pattern = try? NSRegularExpression(
            pattern: #"\{name="([^"]*)",value="([^"]*)",type="([^"]*)",scope="([^"]*)",tkey="([^"]*)"\}"#
        ) else { return [] }
        let ns = raw as NSString
        pattern.enumerateMatches(in: raw, range: NSRange(raw.startIndex..., in: raw)) { match, _, _ in
            guard let match else { return }
            variables.append(DebugVariable(
                name:     ns.substring(with: match.range(at: 1)),
                value:    ns.substring(with: match.range(at: 2)),
                type:     ns.substring(with: match.range(at: 3)),
                scope:    ns.substring(with: match.range(at: 4)),
                tableKey: ns.substring(with: match.range(at: 5))
            ))
        }
        return variables
    }
}
