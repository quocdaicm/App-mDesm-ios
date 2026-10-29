// VesselSheet.swift — màn Bản đồ tàu.

import SwiftUI
import PhotosUI
import WebKit
import MapKit
import CoreLocation
import UserNotifications

struct DesmVesselSheet: View {
    @ObservedObject var model: BrowserModel
    var onClose: () -> Void

    @State private var vessels: [DesmVessel] = []
    @State private var ports: [String: CLLocationCoordinate2D] = DesmPorts.known
    @State private var selected: String? = nil
    @State private var loading = false
    @State private var error = ""
    @State private var tick = 0
    @State private var infos: [String: DesmShipInfo] = [:]
    @State private var infoMsg: [String: String] = [:]
    @State private var infoLoading: Set<String> = []
    let geocoder = CLGeocoder()

    func loadInfo(_ v: DesmVessel) {
        guard infos[v.id] == nil, !infoLoading.contains(v.id) else { return }
        infoLoading.insert(v.id); infoMsg[v.id] = nil
        model.fetchShipInfo(v) { info, err in
            infoLoading.remove(v.id)
            if let info = info { infos[v.id] = info } else { infoMsg[v.id] = err }
        }
    }

    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh"); return f }()

    @ViewBuilder private func detail(_ v: DesmVessel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !v.pl.isEmpty { Text("Packing List: " + v.pl).font(.system(size: 12, weight: .semibold)) }
            if !v.imo.isEmpty { Text("IMO: " + v.imo).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let i = infos[v.id] {
                let extra = [i.status.isEmpty ? "" : "Trạng thái: " + i.status,
                             i.line.isEmpty ? "" : "Hãng tàu: " + i.line,
                             i.bl.isEmpty ? "" : "BL: " + i.bl,
                             i.mode.isEmpty ? "" : i.mode,
                             i.grossKg > 0 ? String(format: "%.0f kg", i.grossKg) : "",
                             i.volume > 0 ? String(format: "%.2f m³", i.volume) : ""].filter { !$0.isEmpty }
                if !extra.isEmpty { Text(extra.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(i.milestones.enumerated()), id: \.element.id) { idx, m in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle().fill(m.done ? Color.green : (m.planned ? Color.orange : Color.gray.opacity(0.35)))
                                    .frame(width: 10, height: 10)
                                if idx < i.milestones.count - 1 {
                                    Rectangle().fill(m.done ? Color.green.opacity(0.6) : Color.gray.opacity(0.25)).frame(width: 2, height: 22)
                                }
                            }
                            HStack {
                                Text(m.title).font(.system(size: 12, weight: m.done ? .semibold : .regular))
                                    .foregroundStyle(m.done ? Color.primary : Color.secondary)
                                Spacer()
                                Text(m.date.map { Self.dayFmt.string(from: $0) + (m.planned ? " (dự kiến)" : "") } ?? "—")
                                    .font(.system(size: 11)).foregroundStyle(m.planned ? Color.orange : Color.secondary)
                            }
                            .padding(.top, -3)
                        }
                    }
                }
            } else if infoLoading.contains(v.id) {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Đang tải tiến trình…").font(.system(size: 11)).foregroundStyle(.secondary) }
            } else if let m = infoMsg[v.id], !m.isEmpty {
                Text(m).font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
                if !v.vessel.isEmpty, let u = URL(string: "https://www.vesselfinder.com/vessels?name=" + (v.vessel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v.vessel)) {
                    Link(destination: u) { Label("Theo dõi tàu", systemImage: "location.magnifyingglass").font(.system(size: 12, weight: .semibold)) }
                }
                if let i = infos[v.id], !i.bl.isEmpty,
                   let u = URL(string: "https://www.google.com/search?q=" + ((i.line + " " + i.bl + " tracking").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? i.bl)) {
                    Link(destination: u) { Label("Tra BL", systemImage: "shippingbox").font(.system(size: 12, weight: .semibold)) }
                }
            }
        }
        .padding(.top, 4)
    }

    func load() {
        loading = true; error = ""
        model.fetchVessels { list, err in
            loading = false; error = err
            vessels = list
            if let s = selected, !list.contains(where: { $0.id == s }) { selected = nil }
            geocodeMissing(list)
        }
    }

    /// Cảng chưa có trong bảng: tra từng cái một bằng CLGeocoder (giới hạn tốc độ của hệ thống).
    func geocodeMissing(_ list: [DesmVessel]) {
        var names: [String] = []
        for v in list { for n in [v.pol, v.pod] where !n.isEmpty && ports[DesmPorts.key(n)] == nil && !names.contains(n) { names.append(n) } }
        func step(_ i: Int) {
            guard i < names.count else { return }
            geocoder.geocodeAddressString(names[i] + " port") { marks, _ in
                if let c = marks?.first?.location?.coordinate { ports[DesmPorts.key(names[i])] = c }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { step(i + 1) }
            }
        }
        step(0)
    }

    var hasPositions: Bool { vessels.contains { $0.lat != nil && $0.lon != nil } }

    func row(_ v: DesmVessel) -> some View {
        let color: Color = v.arrived ? .gray : (v.departed ? .green : Color(red: 0.85, green: 0.65, blue: 0.0))   // xanh = ATD thật, vàng = dự kiến (như web)
        let state = v.arrived ? "Đã đến" : (v.departed ? "Đang đi" : "Chưa khởi hành")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "ferry.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .frame(width: 34, height: 34).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(v.invoice.isEmpty ? "(không có Invoice)" : v.invoice).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if v.arrivingSoon {
                        Text("Sắp đến").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.green, in: Capsule())
                    }
                    Text(state).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                }
                if !v.vessel.isEmpty { Text(v.vessel + (v.mfr.isEmpty ? "" : " · " + v.mfr)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                Text("\(v.pol.isEmpty ? "—" : v.pol) → \(v.pod.isEmpty ? "—" : v.pod)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.tabBlue)
                Text("\(v.departed ? "ATD" : "ETD") \(v.etd.isEmpty ? "-" : v.etd)   ·   \(v.arrived ? "ATA" : "ETA") \(v.eta.isEmpty ? "-" : v.eta)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !v.item.isEmpty { Text(v.item).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(selected == v.id ? 4 : 2) }
                if selected == v.id { detail(v) }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { selected = selected == v.id ? nil : v.id; if selected == v.id { loadInfo(v) } }
        .listRowBackground(selected == v.id ? Color.tabBlue.opacity(0.10) : (v.arrivingSoon ? Color.green.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DesmVesselMap(vessels: vessels, ports: ports, selected: selected, tick: tick)
                    .frame(height: 290)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                if !error.isEmpty {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 6)
                }
                if loading && vessels.isEmpty {
                    Spacer(); ProgressView("Đang tải…"); Spacer()
                } else if vessels.isEmpty {
                    Spacer()
                    Text(error.isEmpty ? "Chưa có chuyến tàu nào." : "").font(.callout).foregroundStyle(.secondary).padding(24)
                    Spacer()
                } else {
                    List(vessels) { v in row(v) }.listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bản đồ tàu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Đóng") { onClose() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
        }
        .onAppear { if vessels.isEmpty && !loading { load() } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }
}
