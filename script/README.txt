SCRIPT FOLDER
=============

Muc dich:
- Chua cac script ho tro phan tich, visualize, va mo phong data flow cho du an In_SOC.
- Day se la noi de phat trien "System Flow Visualizer" ma chung ta vua thong nhat y tuong.

Huong phat trien de xuat:
1. event_timeline.py
2. vcd_parser.py
3. flow_visualizer.py
4. sample_scenarios/

Ghi chu:
- Thu muc nay duoc tao de bat dau phan "tool hoc nhanh tong quan he thong".
- Buoc tiep theo hop ly la tao mot ban v1 doc waveform/log va hien thi timeline cac su kien chinh.

V1 da tao:
- flow_visualizer_v1.js : Doc VCD that va xuat HTML overview/timing/event.
- run_flow_visualizer_v1.cmd : File chay nhanh tren Windows de nhap start/end time.
- output/flow_visualizer_v1.html : File HTML sinh ra sau khi chay script.

Cach dung nhanh:
1. Chay run_flow_visualizer_v1.cmd
2. Nhap start/end theo don vi ps
3. Mo file HTML trong script/output

V2 da tao:
- flow_visualizer_v2.js : Parser/generator cho HTML interactive.
- flow_visualizer_v2_client.js : Logic slider, preset, jump event, timing va explanation trong browser.
- flow_visualizer_v2.css : Giao dien chung cho V2.
- run_flow_visualizer_v2.cmd : File chay nhanh tren Windows de sinh V2.
- output/flow_visualizer_v2.html : File HTML sinh ra sau khi chay V2.

Cach dung nhanh V2:
1. Chay run_flow_visualizer_v2.cmd
2. Nhap start/end theo don vi ps neu muon, hoac de trong de dung mac dinh
3. Mo file HTML trong script/output
4. Trong HTML, dung preset, slider, jump event, va window size de xem luong tin hieu

Y nghia V2:
- Khong chi chup mot cua so co dinh nhu V1, ma cho phep tuong tac ngay tren HTML.
- Hop de hoc luong: Clock/Reset -> SPI/ADC -> DSP -> CPU/APB -> Relay/Watchdog/BIST.

V3 da tao:
- flow_visualizer_v3.js : Doc VCD + RTL top/module definitions de sinh HTML interactive co them so do khoi kien truc.
- flow_visualizer_v3_client.js : Render slider, timing, event, architecture diagram, module port catalog, connection catalog.
- flow_visualizer_v3.css : Giao dien cho V3.
- run_flow_visualizer_v3.cmd : File chay nhanh tren Windows de sinh V3.
- output/flow_visualizer_v3.html : File HTML sinh ra sau khi chay V3.

Cach dung nhanh V3:
1. Chay run_flow_visualizer_v3.cmd
2. Co 3 cach chon VCD:
   - Enter de dung VCD mac dinh cua do an: sim\intelli_safe_arc_test.vcd
   - Nhap tay duong dan VCD moi
   - Keo tha file .vcd vao run_flow_visualizer_v3.cmd
3. Nhap start/end theo don vi ps neu muon, hoac de trong de dung mac dinh
4. Mo file HTML trong script/output
5. Xem theo thu tu: Architecture Diagram -> Module Port Catalog / Connection Catalog -> Controls -> Live Block Flow -> Timing Diagram

Ghi chu quan trong cho V3:
- HTML la mot snapshot. Moi khi doi RTL hoac doi VCD, ban nen chay lai run_flow_visualizer_v3.cmd.
- Script nay luon ghi de vao output\flow_visualizer_v3.html de ban khong phai doi duong dan mo file.
- Summary trong HTML se cho biet VCD nao dang duoc dung.

Y nghia V3:
- Them lop kien truc tinh: module nao co trong top_soc, port nao duoc khai bao, net nao noi giua cac block.
- Giu lop dong cua V2: zoom theo thoi gian, event, timing, block highlight.
- Phu hop de hoc tong quan du an nhanh hon truoc khi lan vao waveform chi tiet.

Neu clone sang do an khac:
- Sua WATCH trong flow_visualizer_v3.js de map dung cac signal quan trong cua do an moi.
- Sua top module / pattern parse neu do an moi khong dung top_soc.
- Sua VCD mac dinh trong run_flow_visualizer_v3.cmd.
- Phan renderer V3 co the tai su dung rat nhieu, thuong chi can sua list signal va mapping block.
