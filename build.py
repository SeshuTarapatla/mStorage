from os import system, path
from shutil import rmtree


class Nuitka:
    @staticmethod
    def build(file):
        try:
            cmd = f'python -m nuitka --onefile "{file}"'
            system(cmd)
        except Exception as e:
            print(e)
        finally:
            cache = ['.build', '.dist', '.onefile-build']
            file = path.split(file)[-1]
            file = path.splitext(file)[0]
            for _dir in cache:
                _dir = file + _dir
                if path.isdir(_dir):
                    rmtree(_dir)


if __name__ == '__main__':
    Nuitka.build('decoder.py')
    Nuitka.build('encoder.py')