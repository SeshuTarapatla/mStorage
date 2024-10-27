# importing necessary libraries
from os import system, path, makedirs
from datetime import datetime
from subprocess import run
from shutil import rmtree


def clear_cache():
    print('Clearing cache           : ', end='', flush=True)
    rmtree('cache')
    print('Done\n')


class Encode:
    def __init__(self) -> None:
        self.time = None
        self.date = None
        self.title = None
        self.srt = None
        self.poster = None
        self.video = None
        
        self.get_input()
        self.rar = 'bin\\rar.exe'
        self.zip = f'cache\\{self.title}.zip'
        self.mask = f'cache\\mask.mp4'
        self.ffmpeg = 'bin\\ffmpeg.exe'
        self.password = '' #Sample password

        self.generate_mask_video()
        self.generate_zip_file()
        self.generate_output_video()
        clear_cache()

    def get_input(self):
        self.video = input('Drag and drop video file: ').replace('"', '')
        print('\nEnter video properties (leave blank for defaults)')
        self.title = input('Title             : ')
        self.date = input('Date (YYYY-MM-DD) : ')
        self.time = input('Time (HH:MM:SS)   : ')
        self.poster = input('Poster            : ').replace('"', '')
        self.srt = input('SRT File          : ').replace('"', '')

        if not self.title: self.title = path.splitext(path.split(self.video)[-1])[0]
        if not self.date: self.date = datetime.now().strftime('%Y-%m-%d')
        print()
        if not self.time: self.time = '07:00:00'

    def generate_mask_video(self):
        makedirs('cache', exist_ok=True)
        if not self.poster:
            self.generate_mask_frame()
            poster = 'cache\\frame.jpg'
        else:
            poster = self.poster
        print('Generating mask video    : ', end='', flush=True)
        cmd = f'{self.ffmpeg} -y -loop 1 -i "{poster}" -c:v libx264 -t 5 -pix_fmt yuv420p -vf "scale=1920:1080" -metadata creation_time="{self.date}T{self.time}" {self.mask}'
        run(cmd, shell=True, capture_output=True)
        print('Done')

    def generate_zip_file(self):
        print('Compressing input to zip : ', end='', flush=True)
        cmd = f'{self.rar} a -p{self.password} -ep1 "{self.zip}" "{self.video}"'
        if self.srt: cmd += f' "{self.srt}"'
        if self.poster: cmd += f' "{self.poster}"'
        system(cmd)
        print('Done')

    def generate_output_video(self):
        print('Generating output video  : ', end='', flush=True)
        with open(self.mask, 'rb') as f:
            mask_data = f.read()
        with open(self.title + '.mp4', 'wb') as f:
            with open(self.zip, 'rb') as z:
                f.write(mask_data)
                f.write(b'\nbreakpoint\n')
                while True:
                    chunk = z.read(10 ** 6)
                    if not chunk: break
                    f.write(chunk)
        print('Done')

    def generate_mask_frame(self):
        pass


if __name__ == '__main__':
    system('cls')
    mov = Encode()
    system('pause')