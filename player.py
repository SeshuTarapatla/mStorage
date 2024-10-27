# importing necessary libraries
from os import environ, path, walk, system
from sys import exit as _exit
from subprocess import Popen


class Player:
    def __init__(self) -> None:
        self.video = None
        self.executable = None

        self.check_syncplay_executable()
        self.select_video()
        self.start_server()

    def check_syncplay_executable(self):
        executable = r"Syncplay\SyncplayConsole.exe"
        if path.isfile(path.join(environ['PROGRAMFILES'], executable)):
            self.executable = path.join(environ['PROGRAMFILES'], executable)
        elif path.isfile(path.join(environ['PROGRAMFILES(x86)'], executable)):
            self.executable = path.join(environ['PROGRAMFILES(x86)'], executable)
        else:
            Player.exit('Syncplay server executable not found')

    def select_video(self):
        vids = []
        formats = ('mp4', 'mov', 'webp', 'mkv')
        filetype = lambda file: path.splitext(file)[1].replace('.', '').lower()
        for d in walk('.'):
            if d[0] in ('.', '.\\bin'): continue
            _vids = list(filter(lambda x: filetype(x) in formats, d[2]))
            vids += list(map(lambda x: path.join(d[0], x), _vids))
        if not vids:
            Player.exit('Cannot find the video file')
        elif len(vids) == 1:
            self.video = vids[0]
        else:
            print('Please select the video for Syncplay...\n')
            for i, vid in enumerate(vids, start=1):
                print(f'{i}. {path.split(vid)[-1]}')
            selection = input('\nSelect the video: ')
            try:
                self.video = vids[int(selection) - 1]
            except IndexError:
                Player.exit('Invalid selection')

    def start_server(self):
        args = [self.executable, self.video]
        Popen(args, shell=True)
        _exit()

    @staticmethod
    def exit(msg):
        print(f'{msg}\n')
        system('pause')
        _exit()


if __name__ == '__main__':
    a = Player()
