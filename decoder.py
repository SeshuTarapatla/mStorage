# importing necessary libraries
from os import system, path, makedirs
from shutil import rmtree


def clear_cache():
    print('Clearing cache            : ', end='', flush=True)
    rmtree('cache')
    print('Done\n')


class Decode:
    def __init__(self) -> None:
        self.title = None
        self.video = None

        self.get_input()
        self.rar = 'bin\\rar.exe'
        self.zip = f'cache\\{self.title}.zip'
        self.password = '' #Sample password

        self.extract_zip()
        self.extract_video()
        clear_cache()

    def get_input(self):
        self.video = input('Drag and drop video file: ').replace('"', '')
        self.title = path.splitext(path.split(self.video)[-1])[0]
        print()

    def extract_zip(self):
        print('Extracting zip from mask  : ', end='', flush=True)
        makedirs('cache', exist_ok=True)
        with open(self.video, 'rb') as f:
            with open(self.zip, 'wb') as z:
                chunk = f.read(10 ** 6).split(b'\nbreakpoint\n')[-1]
                z.write(chunk)
                while True:
                    chunk = f.read(10 ** 6)
                    if not chunk: break
                    z.write(chunk)
        print('Done')

    def extract_video(self):
        print('Extracting video from zip : ', end='', flush=True)
        makedirs(self.title, exist_ok=True)
        cmd = f'{self.rar} x -y -p{self.password} "{self.zip}" "{self.title}"'
        system(cmd)
        print('Done')


if __name__ == '__main__':
    system('cls')
    mov = Decode()
    system('pause')