# Kindle E Ink Temperature cho KOReader

[English](README.md)

Plugin cho phép chọn 15°C, 10°C, 5°C hoặc 0°C khi đọc trên màn E Ink. Bản này mở rộng plugin ép 10°C từng giúp chữ đậm hơn trên một máy Paperwhite 5. Hiệu quả phụ thuộc vào màn và firmware. Menu và thông báo dùng tiếng Anh.

## Cài và thử

1. Thoát KOReader. Chép `kindle-eink-temperature.koplugin` vào `koreader/plugins/`. Nếu đã cài bản cũ, xóa thư mục `ppw5einktemp.koplugin` trước khi mở lại KOReader.
2. Mở KOReader và mở một cuốn sách. Vào **bánh răng → Screen → Kindle E Ink Temperature**.
3. Chọn **Hold 15°C while reading**, **Hold 10°C while reading**, **Hold 5°C while reading** hoặc **Hold 0°C while reading**, rồi lật trang để xem kết quả. Chọn mức khác hoặc **Restore Auto** bất cứ lúc nào.
4. Mức đã chọn có hiệu lực trong phiên KOReader hiện tại. Plugin về Auto khi đóng sách hoặc khi Kindle ngủ, rồi áp lại mức đã chọn khi đọc tiếp trong cùng phiên. Sau khi thoát hẳn và mở lại KOReader, bạn có thể chọn lại mức muốn dùng.

**Show current setting** hiển thị model và driver. Trên MediaTek, mục này đọc nhiệt độ và dải driver đang dùng. Trên NXP, mục này hiển thị nhiệt độ KOReader yêu cầu trong lệnh làm mới màn.

Nếu KOReader treo hoặc báo không trở về Auto, khởi động lại Kindle. Để gỡ, thoát KOReader rồi xóa thư mục `kindle-eink-temperature.koplugin`.

## Tương thích

Plugin nhận diện Paperwhite 1–6, Paperwhite 5 Signature Edition, Oasis 1–3, Voyage và Kindle Basic đời 2014/2016/2019/2022/2024. Menu chỉ hiện khi model, driver và cấu trúc lệnh cập nhật màn cùng khớp. Bản đa máy đã qua mô phỏng. Phản hồi làm chữ rõ hơn ở 10°C đến từ bản PPW5 cũ trên Kindle thật.

Khi báo kết quả, ghi rõ model, firmware, phiên bản KOReader và driver trong mục **Show current setting**. Cho biết kết quả ở từng mức đã thử và sau khi bấm **Restore Auto**. Với chế độ giữ, thử cả ngủ và đánh thức máy.

## Chạy kiểm thử

Từ thư mục gốc repo, chạy `luajit tests/run.lua /duong/dan/toi/koreader`. Dùng gói KOReader đã giải nén có `ffi/linux_fb_h.lua` và `ffi/mxcfb_kindle_h.lua`. Bộ kiểm thử mô phỏng driver để kiểm tra nhận diện mẫu máy, chuyển giữa bốn mức, ngủ và đánh thức máy, cùng việc trả về Auto.
