import sys, uuid
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
import json

def main():
    print(json.dumps({'uuid': str(uuid.uuid4())}, ensure_ascii=False))

if __name__ == '__main__':
    main()
