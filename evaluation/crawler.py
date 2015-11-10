import json
import requests

page = 1
url = 'https://www.vingle.net/api/discover/parties?count=300&page=%s'
headers = {'accept-language':'ko-KR,ko;q=0.8,en-US;q=0.6,en;q=0.4'}
dic = {}

while True:
    r = requests.get(url % page, headers=headers)
    j = json.loads(r.text)

    dic.update({i['id']:i['title_in_language'] for i in j})
    print("Page%s : %s" % (page, len(dic)))

    if len(j) < 300:
        break

    page += 1

with open('names.json','w') as f:
    json.dump(dic, f)
