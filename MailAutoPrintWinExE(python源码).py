import imaplib
import email
import os
import time
import threading
from email.header import decode_header
from email.utils import parseaddr
import tkinter as tk
from tkinter import scrolledtext, messagebox
import subprocess  # 新增

# ===================== 固定服务器配置 =====================
IMAP_SERVER = "imap.qq.com"
IMAP_PORT = 993
SAVE_DIR = os.path.abspath("./mail_attachments")
CHECK_INTERVAL = 10  # 轮询间隔(秒)

processed_ids = set()
is_running = False
thread_task = None

# ===================== 工具函数 =====================
def decode_str(s):
    try:
        value, charset = decode_header(s)[0]
        if charset:
            value = value.decode(charset, errors="ignore")
        return str(value).strip()
    except:
        return s

# ===================== 【修复：图片+文档都能打印】 =====================
def print_file(file_path):
    try:
        ext = os.path.splitext(file_path)[1].lower()
        img_types = [".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tiff"]

        if ext in img_types:
            # 图片：用系统照片打印器打开打印
            subprocess.run(
                ["rundll32", "shimgvw.dll,ImageView_PrintTo", file_path],
                shell=True,
                check=True
            )
            log(f"🖨️  图片打印成功：{os.path.basename(file_path)}")
        else:
            # 文档：原来的方式
            os.startfile(file_path, "print")
            log(f"🖨️  文档打印成功：{os.path.basename(file_path)}")
        return True
    except Exception as e:
        log(f"❌ 打印失败：{str(e)}")
        return False

def save_attachment(part, filename):
    try:
        if not os.path.exists(SAVE_DIR):
            os.makedirs(SAVE_DIR)
        file_path = os.path.join(SAVE_DIR, filename)
        with open(file_path, "wb") as f:
            f.write(part.get_payload(decode=True))
        log(f"✅ 附件已保存：{filename}")
        print_file(file_path)
        return file_path
    except Exception as e:
        log(f"❌ 保存附件失败：{str(e)}")
        return None

def parse_mail(msg):
    subject = decode_str(msg.get("Subject", "无标题"))
    from_name, from_addr = parseaddr(msg.get("From", ""))
    from_name = decode_str(from_name)
    log(f"📩 新邮件 | 发件人：{from_name} | 标题：{subject}")

    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        if part.get("Content-Disposition") is None:
            continue
        filename = decode_str(part.get_filename())
        if filename:
            save_attachment(part, filename)

def check_new_mail(user, pwd):
    try:
        mail = imaplib.IMAP4_SSL(IMAP_SERVER, IMAP_PORT)
        mail.login(user, pwd)
        mail.select("INBOX", readonly=True)

        status, mail_data = mail.search(None, "ALL")
        mail_ids = mail_data[0].split()
        if not mail_ids:
            mail.logout()
            return

        for mid in reversed(mail_ids):
            if mid not in processed_ids:
                processed_ids.add(mid)
                res, data = mail.fetch(mid, "(RFC822)")
                msg = email.message_from_bytes(data[0][1])
                parse_mail(msg)
        mail.logout()
    except Exception as e:
        log(f"⚠️  邮箱连接异常：{str(e)}")

def listen_loop(user, pwd):
    global is_running
    while is_running:
        check_new_mail(user, pwd)
        time.sleep(CHECK_INTERVAL)

def log(text):
    def _inner():
        log_box.insert(tk.END, text + "\n")
        log_box.see(tk.END)
    root.after(0, _inner)

# ===================== 按钮事件 =====================
def start_listen():
    global is_running, thread_task
    if is_running:
        messagebox.showinfo("提示", "监听已在运行中！")
        return

    email_user = entry_email.get().strip()
    email_pwd = entry_pwd.get().strip()

    if not email_user or not email_pwd:
        messagebox.showerror("错误", "请填写完整邮箱账号和授权码！")
        return

    is_running = True
    btn_start.config(state=tk.DISABLED)
    btn_stop.config(state=tk.NORMAL)
    entry_email.config(state=tk.DISABLED)
    entry_pwd.config(state=tk.DISABLED)

    log("========================================")
    log(f"▶️  已登录账号：{email_user}")
    log("▶️  邮件监听已启动，等待新邮件...")
    log(f"📂 附件保存目录：{SAVE_DIR}")

    thread_task = threading.Thread(target=listen_loop, args=(email_user, email_pwd), daemon=True)
    thread_task.start()

def stop_listen():
    global is_running
    if not is_running:
        messagebox.showinfo("提示", "当前未开启监听！")
        return
    is_running = False
    btn_start.config(state=tk.NORMAL)
    btn_stop.config(state=tk.DISABLED)
    entry_email.config(state=tk.NORMAL)
    entry_pwd.config(state=tk.NORMAL)
    log("⏹️  邮件监听已停止")

def clear_log():
    log_box.delete(1.0, tk.END)

def on_close():
    global is_running
    is_running = False
    root.destroy()

# ===================== 界面布局 =====================
root = tk.Tk()
root.title("QQ邮件自动打印工具")
root.geometry("780x550")
root.resizable(False, False)

frame_account = tk.Frame(root, padx=10, pady=8)
frame_account.pack(fill=tk.X)

tk.Label(frame_account, text="QQ邮箱账号：", width=12).grid(row=0, column=0, sticky=tk.W)
entry_email = tk.Entry(frame_account, font=("微软雅黑", 10), width=40)
entry_email.grid(row=0, column=1, padx=5)

tk.Label(frame_account, text="授权码：", width=12).grid(row=1, column=0, sticky=tk.W, pady=5)
entry_pwd = tk.Entry(frame_account, font=("微软雅黑", 10), width=40, show="*")
entry_pwd.grid(row=1, column=1, padx=5)

frame_btn = tk.Frame(root, padx=10, pady=5)
frame_btn.pack(fill=tk.X)

btn_start = tk.Button(frame_btn, text="开始监听", command=start_listen, width=12, height=2)
btn_start.pack(side=tk.LEFT, padx=8)

btn_stop = tk.Button(frame_btn, text="停止监听", command=stop_listen, width=12, height=2, state=tk.DISABLED)
btn_stop.pack(side=tk.LEFT, padx=8)

btn_clear = tk.Button(frame_btn, text="清空日志", command=clear_log, width=12, height=2)
btn_clear.pack(side=tk.LEFT, padx=8)

log_box = scrolledtext.ScrolledText(root, font=("微软雅黑", 9))
log_box.pack(padx=10, pady=8, fill=tk.BOTH, expand=True)

root.protocol("WM_DELETE_WINDOW", on_close)

if __name__ == "__main__":
    root.mainloop()
