import base64
import os
import re
import time
import requests
import logging
from requests.adapters import HTTPAdapter, Retry
from pypsrp.encryption import WinRMEncryption
from spnego import client as spengo_client
from spnego._credential import KerberosKeytab

MIME_BOUNDARY = WinRMEncryption.MIME_BOUNDARY.lstrip('--')
HOST = 'stream.cribl.local:5986'

logger = logging.getLogger(__name__)
logging.basicConfig(level=os.environ.get('LOG_LEVEL', 'INFO').upper())

retries = Retry(total=5,
                backoff_factor=5,
                status_forcelist=[401, 403, 500, 502, 503, 504])
session = requests.Session()
session.mount('http://', HTTPAdapter(max_retries=retries))

# Setup Kerberos context
# Using the KerberosKeytab class eliminates the need to run `kinit`
credentials = [KerberosKeytab(keytab="/var/lib/keytab/client.keytab", principal="client")]
krb_context = spengo_client(credentials, hostname="stream.cribl.local", service="http", protocol="kerberos")
auth_token = krb_context.step()

auth_url = f"http://{HOST}/wsman"
auth_headers = {
    'Host': f'{HOST}',
    'Authorization': f'Kerberos {base64.b64encode(auth_token).decode('utf-8')}',
}
auth_response = session.post(auth_url, headers=auth_headers)
krb_header = auth_response.headers.get('www-authenticate').lstrip('Kerberos ')

logger.info(f"Auth Response status code: {auth_response.status_code}")
logger.debug(f"Auth Response content: {krb_header}")

response = base64.b64decode(krb_header)
krb_context.step(response)

# https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wsmv/7818e594-e114-4b72-bfbc-89d900211dca
with open('events.xml', 'rb') as f:
    s = f.read()

# Message bodies are wrapped using Kerberos encryption. A sample payload format can be found here:
# https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wsmv/c6fbab1d-01bc-4733-8710-eeea99cb3b80
# The pypsrp library handles this for us natively using the provided Kerberos authentication context
encryption = WinRMEncryption(krb_context, WinRMEncryption.KERBEROS)
soap_url = f"{auth_url}/subscriptions/WEC"

while True:
    content_type, encrypted_msg = encryption.wrap_message(s)

    soap_headers = {
        'Host': f'{HOST}',
        'Content-Type': f'{content_type};protocol="{WinRMEncryption.KERBEROS}";boundary="{MIME_BOUNDARY}"',
    }

    logger.info(f"Sending message to {soap_url}")
    logger.debug(f"Client request [raw] {s.decode('utf-8')}")
    logger.debug(f"Client request [encoded]: {encrypted_msg.decode('latin1')}")
    soap_response = session.post(soap_url, headers=soap_headers, data=encrypted_msg)

    logger.info(f"Server response status code: {soap_response.status_code}")
    logger.debug(f"Server response headers: {soap_response.headers}")

    if soap_response.headers.get('Content-Type') == 'application/soap+xml;charset=UTF-8':
        # Message is plain-text, just display it
        logger.debug(f"Server response: {soap_response.text}")
    else:
        # We use latin1 to force 1-byte representation, otherwise using utf-8 decoding fails
        response = soap_response.content.decode('latin1')
        logger.debug(f"Server response [raw]: {response}")

        # Looks like Cribl didn't include a tab at the beginning of the message payload headers lines
        # `pypsrp` is expecting this tab because the MS-WSMV spec specifies the horizontal
        # tab character must precede the Content-Type header:
        # https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wsmv/0dbd98e8-8d62-49a8-942c-da5054c364f5
        # so we add the tab, otherwise a gss_iov_unwrap error is thrown because of an
        # incorrect header passed to the winrm_unwrap method
        encrypted_msg = re.sub(r'Content-Type:', '\tContent-Type:', response).encode('latin1')

        unwapped_response = encryption.unwrap_message(encrypted_msg, MIME_BOUNDARY)
        logger.debug(f"Server response [decoded]: {unwapped_response.decode('utf-8')}")

    logger.info(f'Sleeping for 5 seconds...')
    time.sleep(5)
