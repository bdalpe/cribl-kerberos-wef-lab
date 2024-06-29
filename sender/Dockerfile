FROM python:slim-bookworm

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -qq update
RUN apt-get -qq install krb5-user gcc libkrb5-dev
RUN apt-get -qq clean

WORKDIR /app

ADD requirements.txt ./

RUN pip install -r requirements.txt

ADD index.py ./

CMD ["python3", "index.py"]
