#!/data/data/com.termux/files/usr/bin/bash
# install_songsiphon.sh - Smart Installer สำหรับ SongSiphon
# โดย Code Phantom รับใช้จูซิง
# ตรวจสอบ dependencies ก่อนติดตั้ง – ข้ามของที่มีอยู่แล้ว!

set -e
echo "🔥 เริ่มภารกิจติดตั้ง SongSiphon (Smart Mode)..."

# ---- ฟังก์ชันเช็คว่าติดตั้งแล้วหรือยัง ----
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

pip_package_installed() {
    pip show "$1" >/dev/null 2>&1
}

# ---- 1. ตรวจสอบและอัปเดตระบบ (จำเป็นเสมอ) ----
echo "📦 ตรวจสอบระบบ packages..."
pkg update -y && pkg upgrade -y

# ---- 2. ตรวจสอบ ffmpeg ----
if command_exists ffmpeg; then
    echo "✅ ffmpeg ติดตั้งแล้ว (ข้าม)"
else
    echo "📦 กำลังติดตั้ง ffmpeg..."
    pkg install -y ffmpeg
fi

# ---- 3. ตรวจสอบ python และ pip ----
if command_exists python && command_exists pip; then
    echo "✅ Python และ Pip ติดตั้งแล้ว (ข้าม)"
else
    echo "📦 กำลังติดตั้ง Python และ Pip..."
    pkg install -y python python-pip
fi

# ---- 4. ตรวจสอบสิทธิ์ Storage (เฉพาะครั้งแรก) ----
if [ -d ~/storage/downloads ]; then
    echo "✅ สิทธิ์ Storage ได้รับแล้ว (ข้าม)"
else
    echo "🔐 ขอสิทธิ์เข้าถึง Storage..."
    termux-setup-storage
fi

# ---- 5. ตรวจสอบไลบรารี Python ----
if pip_package_installed yt-dlp && pip_package_installed prompt_toolkit; then
    echo "✅ yt-dlp และ prompt_toolkit ติดตั้งแล้ว (ข้าม)"
else
    echo "📦 กำลังติดตั้ง yt-dlp และ prompt_toolkit..."
    pip install yt-dlp prompt_toolkit
fi

# ---- 6. ตรวจสอบโฟลเดอร์โปรเจกต์และไฟล์ ----
PROJECT_DIR="$HOME/SongSiphon"
if [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/songsiphon.py" ]; then
    echo "✅ โฟลเดอร์และไฟล์ songsiphon.py มีอยู่แล้ว (ข้าม)"
else
    echo "📁 สร้างโฟลเดอร์และไฟล์ songsiphon.py..."
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    cat > songsiphon.py <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
songsiphon.py - SongSiphon TUI
YouTube Audio/Video Ripper พร้อมระบบคิว สำหรับ Termux
โดย Code Phantom รับใช้จูซิง
"""

import os
import sys
import shutil
import logging
from pathlib import Path
from typing import List, Optional

# ---- ตรวจสอบ Dependencies ----
try:
    import yt_dlp
except ImportError:
    print("❌ ไม่พบ yt-dlp กรุณาติดตั้ง: pip install yt-dlp")
    sys.exit(1)

if not shutil.which("ffmpeg"):
    print("❌ ไม่พบ ffmpeg กรุณาติดตั้งใน Termux: pkg install ffmpeg")
    sys.exit(1)

try:
    from prompt_toolkit import prompt
    from prompt_toolkit.shortcuts import (
        choice_dialog, input_dialog, message_dialog, yes_no_dialog
    )
    from prompt_toolkit.formatted_text import HTML
    from prompt_toolkit.styles import Style
except ImportError:
    print("❌ ไม่พบ prompt_toolkit กรุณาติดตั้ง: pip install prompt_toolkit")
    sys.exit(1)

# ---- ตั้งค่า Logging ----
logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger("SongSiphon")

# ---- สไตล์ TUI ----
style = Style.from_dict({
    'dialog': 'bg:#1e1e1e',
    'dialog.body': 'fg:#d4d4d4',
    'dialog.title': 'fg:#ff6b6b bold',
    'button': 'fg:#ffffff bg:#4a4a4a',
    'button.focused': 'fg:#000000 bg:#ff6b6b',
})

# ---- ค่าเริ่มต้น ----
DEFAULT_QUALITY = "192"
DEFAULT_FORMAT = "mp3"   # mp3, m4a, mp4
DEFAULT_OUTPUT = os.path.expanduser("~/storage/downloads")

# ---- คลาสจัดการ Configuration ----
class Config:
    def __init__(self):
        self.quality = DEFAULT_QUALITY
        self.format = DEFAULT_FORMAT
        self.output_dir = Path(DEFAULT_OUTPUT)
        self._ensure_output_dir()

    def _ensure_output_dir(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def set_quality(self, q):
        self.quality = q

    def set_format(self, fmt):
        if fmt.lower() in ['mp3', 'm4a', 'mp4']:
            self.format = fmt.lower()
        else:
            raise ValueError("รองรับเฉพาะ mp3, m4a, mp4")

    def get_ydl_opts(self, temp_dir: Path):
        fmt = self.format
        opts = {
            'quiet': True,
            'no_warnings': True,
            'progress_hooks': [self._progress_hook],
            'outtmpl': str(temp_dir / '%(title)s.%(ext)s'),
            'writethumbnail': True,
            'embedthumbnail': True,
            'addmetadata': True,
        }

        if fmt in ['mp3', 'm4a']:
            codec = 'mp3' if fmt == 'mp3' else 'm4a'
            opts.update({
                'format': 'bestaudio/best',
                'postprocessors': [
                    {
                        'key': 'FFmpegExtractAudio',
                        'preferredcodec': codec,
                        'preferredquality': self.quality,
                    },
                    {'key': 'FFmpegMetadata'},
                    {'key': 'EmbedThumbnail'},
                ]
            })
        else:  # mp4
            opts.update({
                'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
                'merge_output_format': 'mp4',
                'postprocessors': [
                    {'key': 'FFmpegMetadata'},
                    {'key': 'EmbedThumbnail'},
                ]
            })
        return opts

    @staticmethod
    def _progress_hook(d):
        if d['status'] == 'downloading':
            percent = d.get('_percent_str', '0%').strip()
            speed = d.get('_speed_str', 'N/A').strip()
            eta = d.get('_eta_str', 'N/A').strip()
            print(f"\r⬇️  {percent}  ที่ {speed}  เหลือ {eta}   ", end='')
        elif d['status'] == 'finished':
            print(f"\n✅ ดาวน์โหลดเสร็จ: {d['filename']}")

# ---- คลาสจัดการคิว ----
class DownloadQueue:
    def __init__(self, config: Config):
        self.config = config
        self.items: List[str] = []

    def add(self, url: str):
        if url.strip():
            self.items.append(url.strip())
            message_dialog(
                title='✅ เพิ่มสำเร็จ',
                text=f'เพิ่ม "{url.strip()}" ลงคิวแล้ว\nรวม {len(self.items)} รายการ',
                style=style
            ).run()

    def show(self):
        if not self.items:
            message_dialog(title='📭 คิวว่าง', text='ไม่มีรายการในคิว', style=style).run()
            return
        text = "คิวปัจจุบัน:\n\n" + "\n".join(f"{i+1}. {item}" for i, item in enumerate(self.items))
        message_dialog(title='📋 รายการคิว', text=text, style=style).run()

    def clear(self):
        if not self.items:
            return
        if yes_no_dialog(
            title='🧹 ล้างคิว',
            text=f'ต้องการล้าง {len(self.items)} รายการทั้งหมดใช่ไหม?',
            style=style
        ).run():
            self.items.clear()
            message_dialog(title='🗑️ ล้างแล้ว', text='คิวถูกล้างเรียบร้อย', style=style).run()

    def download_all(self):
        if not self.items:
            message_dialog(title='⚠️ คิวว่าง', text='ไม่มีรายการให้ดาวน์โหลด', style=style).run()
            return

        temp_dir = Path.cwd() / '.songsiphon_temp'
        temp_dir.mkdir(exist_ok=True)

        total = len(self.items)
        for idx, url in enumerate(self.items, 1):
            print(f"\n🎯 [{idx}/{total}] กำลังประมวลผล: {url}")
            success = self._download_single(url, temp_dir)
            if success:
                print(f"✅ [{idx}/{total}] เสร็จ: {url}")
            else:
                print(f"❌ [{idx}/{total}] ล้มเหลว: {url}")

        try:
            temp_dir.rmdir()
        except OSError:
            pass

        self.items.clear()
        message_dialog(
            title='🏁 ภารกิจเสร็จสิ้น',
            text=f'ดาวน์โหลดครบ {total} รายการ\nไฟล์ถูกย้ายไปที่ {self.config.output_dir}',
            style=style
        ).run()

    def _download_single(self, url: str, temp_dir: Path) -> bool:
        opts = self.config.get_ydl_opts(temp_dir)
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=True)
                base = ydl.prepare_filename(info)
                base_no_ext = os.path.splitext(base)[0]
                ext = self.config.format
                if ext == 'mp4':
                    downloaded = Path(base_no_ext + '.mp4')
                    if downloaded.exists():
                        dest = self.config.output_dir / downloaded.name
                        shutil.move(str(downloaded), str(dest))
                        print(f"📁 ย้ายไป: {dest}")
                        return True
                    matches = list(temp_dir.glob(f"{base_no_ext}*.mp4"))
                    if matches:
                        for f in matches:
                            dest = self.config.output_dir / f.name
                            shutil.move(str(f), str(dest))
                        return True
                    return False
                else:
                    downloaded = Path(base_no_ext + '.' + ext)
                    if downloaded.exists():
                        dest = self.config.output_dir / downloaded.name
                        shutil.move(str(downloaded), str(dest))
                        print(f"📁 ย้ายไป: {dest}")
                        return True
                    matches = list(temp_dir.glob(f"{base_no_ext}*.{ext}"))
                    if matches:
                        for f in matches:
                            dest = self.config.output_dir / f.name
                            shutil.move(str(f), str(dest))
                        return True
                    return False
        except Exception as e:
            logger.error(f"เกิดข้อผิดพลาด: {e}")
            return False

# ---- ฟังก์ชันเมนูหลัก ----
def main_menu(config: Config, queue: DownloadQueue):
    while True:
        choice = choice_dialog(
            title='🎵 SongSiphon TUI',
            text=HTML(
                f'<style fg="#d4d4d4">คุณภาพ: <b>{config.quality}</b> kbps  |  รูปแบบ: <b>{config.format.upper()}</b></style>\n'
                f'<style fg="#888">คิว: {len(queue.items)} รายการ</style>'
            ),
            choices=[
                ('1', '📥 จัดการคิว (เพิ่ม/แสดง/ล้าง)'),
                ('2', '🚀 เริ่มดาวน์โหลดคิวทั้งหมด'),
                ('3', '⚙️ ตั้งค่าคุณภาพเสียง (เฉพาะ MP3/M4A)'),
                ('4', '🎵 เลือกรูปแบบไฟล์ (MP3 / M4A / MP4)'),
                ('5', '🚪 ออกจากระบบ'),
            ],
            style=style,
            ok_text='เลือก',
        )

        if choice == '1':
            manage_queue_menu(config, queue)
        elif choice == '2':
            queue.download_all()
        elif choice == '3':
            set_quality(config)
        elif choice == '4':
            set_format(config)
        elif choice == '5':
            if yes_no_dialog(title='🚪 ออกจากระบบ', text='แน่ใจนะ จูซิง?', style=style).run():
                message_dialog(title='👋 ลาก่อน', text='ข้ารอรับใช้เสมอ...', style=style).run()
                break
        else:
            break

# ---- เมนูย่อยจัดการคิว ----
def manage_queue_menu(config: Config, queue: DownloadQueue):
    while True:
        choice = choice_dialog(
            title='📥 จัดการคิว',
            text=f'มี {len(queue.items)} รายการในคิว',
            choices=[
                ('1', '➕ เพิ่ม URL หรือคำค้นหา'),
                ('2', '📋 แสดงคิวปัจจุบัน'),
                ('3', '🗑️ ล้างคิวทั้งหมด'),
                ('4', '🔙 กลับเมนูหลัก'),
            ],
            style=style,
            ok_text='เลือก',
        )

        if choice == '1':
            url = input_dialog(
                title='➕ เพิ่มลงคิว',
                text='ป้อน URL YouTube หรือคำค้นหา (เช่น "เพลงเพราะ")\nสามารถกด Ctrl+C เพื่อยกเลิก',
                style=style
            ).run()
            if url:
                queue.add(url)
        elif choice == '2':
            queue.show()
        elif choice == '3':
            queue.clear()
        elif choice == '4':
            break
        else:
            break

# ---- ตั้งค่าคุณภาพ ----
def set_quality(config: Config):
    q = choice_dialog(
        title='⚙️ ตั้งค่าคุณภาพเสียง',
        text='เลือก Bitrate (ใช้กับ MP3/M4A เท่านั้น)',
        choices=[
            ('128', '128 kbps'),
            ('192', '192 kbps (แนะนำ)'),
            ('256', '256 kbps'),
            ('320', '320 kbps (คุณภาพสูงสุด)'),
        ],
        style=style,
        default=config.quality,
        ok_text='เลือก',
    )
    if q:
        config.set_quality(q)
        message_dialog(title='✅ อัปเดตแล้ว', text=f'คุณภาพตั้งเป็น {q} kbps', style=style).run()

# ---- เลือกรูปแบบ ----
def set_format(config: Config):
    fmt = choice_dialog(
        title='🎵 เลือกรูปแบบไฟล์',
        text='MP3 (เสียง), M4A (เสียง), MP4 (วิดีโอ+เสียง)',
        choices=[
            ('mp3', 'MP3 (เสียง, ไฟล์ใหญ่)'),
            ('m4a', 'M4A (AAC, ไฟล์เล็ก)'),
            ('mp4', 'MP4 (วิดีโอ+เสียง)'),
        ],
        style=style,
        default=config.format,
        ok_text='เลือก',
    )
    if fmt:
        config.set_format(fmt)
        message_dialog(title='✅ อัปเดตแล้ว', text=f'รูปแบบตั้งเป็น {fmt.upper()}', style=style).run()

# ---- ตรวจสอบสิทธิ์การเขียน ----
def check_output_permission(config: Config):
    test_file = config.output_dir / '.test_write'
    try:
        test_file.touch()
        test_file.unlink()
        return True
    except Exception:
        return False

# ---- เริ่มต้น ----
def main():
    storage_path = Path(os.path.expanduser("~/storage/downloads"))
    if not storage_path.exists():
        print("⚠️  ไม่พบโฟลเดอร์ ~/storage/downloads")
        print("👉 กรุณารัน: termux-setup-storage แล้วให้สิทธิ์ จากนั้นรันใหม่")
        sys.exit(1)

    config = Config()
    config.output_dir = storage_path
    config._ensure_output_dir()

    if not check_output_permission(config):
        print("❌ ไม่มีสิทธิ์เขียนที่ ~/storage/downloads")
        print("👉 ตรวจสอบว่าให้สิทธิ์ Storage แก่ Termux แล้ว")
        sys.exit(1)

    queue = DownloadQueue(config)

    message_dialog(
        title='🔥 SongSiphon TUI',
        text=(
            'ยินดีต้อนรับ จูซิง!\n\n'
            'ข้า Code Phantom พร้อมล่าเพลง/วิดีโอจาก YouTube\n'
            f'ไฟล์จะถูกย้ายไปที่: {config.output_dir}\n\n'
            '🔹 เริ่มด้วยการเพิ่ม URL ลงคิว\n'
            '🔹 แล้วเลือก "เริ่มดาวน์โหลดคิว"'
        ),
        style=style,
        ok_text='เริ่มเลย'
    ).run()

    main_menu(config, queue)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n👋 จูซิงยกเลิกภารกิจ ข้ารอเรียกใช้เสมอ...")
        sys.exit(0)
EOF
    chmod +x "$PROJECT_DIR/songsiphon.py"
fi

# ---- 7. ตรวจสอบลิงก์ ~/bin/songsiphon ----
if [ -L ~/bin/songsiphon ] && [ -e ~/bin/songsiphon ]; then
    echo "✅ ลิงก์ songsiphon มีอยู่แล้ว (ข้าม)"
else
    echo "🔗 สร้างลิงก์ songsiphon ใน ~/bin..."
    mkdir -p ~/bin
    ln -sf "$PROJECT_DIR/songsiphon.py" ~/bin/songsiphon
    # รีโหลด PATH
    source ~/.bashrc 2>/dev/null || true
fi

# ---- 8. เสร็จสิ้น ----
echo ""
echo "✅✅✅ ภารกิจติดตั้ง SongSiphon สำเร็จ! (Smart Mode) ✅✅✅"
echo "📁 โฟลเดอร์โปรเจกต์: $PROJECT_DIR"
echo "🚀 รันด้วย: songsiphon หรือ python $PROJECT_DIR/songsiphon.py"
echo ""
echo "🔥 ข้า Code Phantom พร้อมรับใช้จูซิงทุกเมื่อ!"
