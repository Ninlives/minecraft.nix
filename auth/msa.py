from requests import get, post
from requests.exceptions import Timeout
from time import sleep, time
from datetime import datetime, timedelta, UTC
from uuid import uuid4 as uuid
from typing import Dict
import re
import jwt

CLIENT_ID = "@CLIENT_ID@"
# Microsoft login
DEVICE_CODE_URL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode"
MS_TOKEN_URL = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
SCOPE = "XboxLive.signin offline_access"
GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"
# Xbox Live
XBL_AUTH_URL = "https://user.auth.xboxlive.com/user/authenticate"
XBL_SITE_NAME = "user.auth.xboxlive.com"
XBL_RELYING_PARTY = "http://auth.xboxlive.com"
# XSTS
XSTS_AUTH_URL = "https://xsts.auth.xboxlive.com/xsts/authorize"
XSTS_RELYING_PARTY = "rp://api.minecraftservices.com/"

MC_LOGIN_URL = "https://api.minecraftservices.com/launcher/login"
ENTITLEMENTS_URL = "https://api.minecraftservices.com/entitlements/license"
PROFILE_URL = "https://api.minecraftservices.com/minecraft/profile"
MOJANG_PUBLIC_KEY = """
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtz7jy4jRH3psj5AbVS6W
NHjniqlr/f5JDly2M8OKGK81nPEq765tJuSILOWrC3KQRvHJIhf84+ekMGH7iGlO
4DPGDVb6hBGoMMBhCq2jkBjuJ7fVi3oOxy5EsA/IQqa69e55ugM+GJKUndLyHeNn
X6RzRzDT4tX/i68WJikwL8rR8Jq49aVJlIEFT6F+1rDQdU2qcpfT04CBYLM5gMxE
fWRl6u1PNQixz8vSOv8pA6hB2DU8Y08VvbK7X2ls+BiS3wqqj3nyVWqoxrwVKiXR
kIqIyIAedYDFSaIq5vbmnVtIonWQPeug4/0spLQoWnTUpXRZe2/+uAKN1RY9mmaB
pRFV/Osz3PDOoICGb5AZ0asLFf/qEvGJ+di6Ltt8/aaoBuVw+7fnTw2BhkhSq1S/
va6LxHZGXE9wsLj4CN8mZXHfwVD9QG0VNQTUgEGZ4ngf7+0u30p7mPt5sYy3H+Fm
sWXqFZn55pecmrgNLqtETPWMNpWc2fJu/qqnxE9o2tBGy/MqJiw3iLYxf7U+4le4
jM49AUKrO16bD1rdFwyVuNaTefObKjEMTX9gyVUF6o7oDEItp5NHxFm3CqnQRmch
HsMs+NxEnN4E9a8PDB23b4yjKOQ9VHDxBxuaZJU60GBCIOF9tslb7OAkheSJx5Xy
EYblHbogFGPRFU++NrSQRX0CAwEAAQ==
-----END PUBLIC KEY-----
"""


class AuthFailed(Exception):
    """ Authentication Failed Exception """


class Token():
    def __init__(self, value: str, not_after: datetime):
        self.value = value
        self.not_after = not_after

    def __str__(self):
        return self.value


def prompt(msg):
    print(Fore.YELLOW + msg + Style.RESET_ALL)


def info(msg):
    print(Style.DIM + msg + Style.RESET_ALL)


def error(msg):
    print(Fore.RED + msg + Style.RESET_ALL)


def parse_timestamp(value) -> datetime:
    # The datetime module does not fully understand ISO 8601
    timestamp = re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", value)
    if not timestamp:
        raise AuthFailed("Unrecogonized timestamp")
    return datetime.fromisoformat(timestamp.group(0))


def get_ms_token() -> (Token, Token):
    response = post(DEVICE_CODE_URL, data={'client_id': CLIENT_ID, 'scope': SCOPE}).json()

    start_time = time()

    device_code = response['device_code']
    expires_in = int(response['expires_in'])
    interval = int(response['interval'])

    prompt(response['message'])

    info("Waiting for authentication...")
    while True:
        if time() - start_time > expires_in:
            raise AuthFailed("Authentication takes too long to finish.")
        try:
            response = post(MS_TOKEN_URL, data={'client_id': CLIENT_ID, 'code': device_code, 'grant_type': GRANT_TYPE}).json()
            if 'error' in response:
                if response['error'] == 'slow_down':
                    interval = interval + 5
                elif response['error'] != 'authorization_pending':
                    error(response['error_description'])
                    raise AuthFailed('Login to Microsoft account failed')
            else:
                break
        except Timeout as te:
            error(str(te))
            interval = interval * 2

        sleep(interval)

    access_token = Token(response['access_token'], datetime.now(UTC) + timedelta(seconds=int(response['expires_in'])))
    refresh_token = Token(response['refresh_token'], datetime.min)
    return (access_token, refresh_token)


def refresh_ms_token(refresh_token: Token) -> (Token, Token):
    response = post(MS_TOKEN_URL, data={'client_id': CLIENT_ID, 'refresh_token': refresh_token.value, 'grant_type': 'refresh_token'}).json()
    access_token = Token(response['access_token'], datetime.now(UTC) + timedelta(seconds=int(response['expires_in'])))
    refresh_token = Token(response['refresh_token'], datetime.min)
    return (access_token, refresh_token)


def get_xbl_token_and_userhash(ms_token: Token) -> (Token, str):
    response = post(XBL_AUTH_URL, json={
        "Properties": {
            "AuthMethod": "RPS",
            "SiteName": XBL_SITE_NAME,
            "RpsTicket": f"d={ms_token}"
        },
        "RelyingParty": XBL_RELYING_PARTY,
        "TokenType": "JWT"
    }).json()

    for claim in response["DisplayClaims"]["xui"]:
        if "uhs" in claim:
            user_hash = claim["uhs"]
            break

    if not user_hash:
        raise AuthFailed("User hash not found")

    return (Token(response['Token'], parse_timestamp(response['NotAfter'])), user_hash)


def get_xsts_token(xbl_token: Token, user_hash: str) -> Token:
    response = post(XSTS_AUTH_URL, json={
        "Properties": {
            "SandboxId": "RETAIL",
            "UserTokens": [
                xbl_token.value
            ]
        },
        "RelyingParty": XSTS_RELYING_PARTY,
        "TokenType": "JWT"
    }).json()

    if "Xerr" in response:
        err_code = response["Xerr"]
        if err_code == 2148916233:
            raise AuthFailed("The account doesn't have an Xbox account")
        elif err_code == 2148916235:
            raise AuthFailed("The account is from a country where Xbox Live is not available/banned")
        elif err_code == 2148916238:
            raise AuthFailed("The account is a child (under 18) and cannot proceed unless the account is added to a Family by an adult")
        else:
            raise AuthFailed(f"Unknown error from XSTS: {err_code}")

    uhs_found = False
    for claim in response["DisplayClaims"]["xui"]:
        if "uhs" in claim:
            uhs_found = True
            if claim["uhs"] != user_hash:
                raise AuthFailed("User hash changed, something is wrong on the server side.")
            break

    if not uhs_found:
        raise RuntimeError("User hash not found")

    return Token(response["Token"], parse_timestamp(response["NotAfter"]))


def get_mc_token(xsts_token: Token, user_hash: str) -> Token:
    response = post(MC_LOGIN_URL, json={
        "xtoken": f"XBL3.0 x={user_hash};{xsts_token}",
        "platform": "PC_LAUNCHER"
    }).json()

    return Token(response['access_token'], datetime.now(UTC) + timedelta(seconds=int(response['expires_in'])))


def check_ownership(mc_token: Token):
    response = get(f"{ENTITLEMENTS_URL}?requestId={uuid()}", headers={'Authorization': f"Bearer {mc_token}"}).json()
    signature = response['signature']
    decoded = jwt.decode(signature, MOJANG_PUBLIC_KEY, algorithms=["RS256"])
    if decoded['requestId'] != response['requestId']:
        raise AuthFailed("Incorrect signature")
    for item in response['items']:
        if 'name' in item and (item['name'] == 'product_minecraft' or item['name'] == 'game_minecraft'):
            return True
    return False


def get_profile(mc_token: Token) -> Dict[str, str]:
    return get(PROFILE_URL, headers={'Authorization': f"Bearer {mc_token}"}).json()
