import json
from datetime import datetime
from os.path import expanduser
from sys import argv
from pathlib import Path
from colorama import Fore, Style


def get_mc_token_from_ms_token(ms_token):
    info("Logging in as an Xbox user.")
    (xbl_token, user_hash) = get_xbl_token_and_userhash(ms_token)
    info("Getting authorization to access Xbox services.")
    xsts_token = get_xsts_token(xbl_token, user_hash)
    info("Getting authorization to access Mojang services.")
    return get_mc_token(xsts_token, user_hash)


def login_and_get_profile():
    info("Logging in with Microsoft account.")
    (ms_token, refresh_token) = get_ms_token()
    mc_token = get_mc_token_from_ms_token(ms_token)

    info("Determining game ownership.")
    if check_ownership(mc_token):
        profile = get_profile(mc_token)
        profile['mc_token'] = mc_token
        profile['refresh_token'] = refresh_token
        return profile
    else:
        raise AuthFailed("User does not own the game")


def refresh(profile):
    info("Logging in with Microsoft refresh token.")
    (new_ms_token, new_refresh_token) = refresh_ms_token(profile['refresh_token'])
    new_mc_token = get_mc_token_from_ms_token(new_ms_token)
    profile['mc_token'] = new_mc_token
    profile['refresh_token'] = new_refresh_token


def custom_encode(obj):
    if isinstance(obj, Token):
        return {'__type': 'Token', '__value': obj.value, '__not_after': obj.not_after.isoformat()}
    return json.JSONEncoder.default(obj)


def custom_decode(dct):
    if '__type' in dct and dct['__type'] == 'Token':
        return Token(dct['__value'], datetime.fromisoformat(dct['__not_after']))
    return dct


def authenticate(profile_path):
    if profile_path.exists():
        try:
            with open(profile_path) as f:
                profile = json.load(f, object_hook=custom_decode)
        except json.JSONDecodeError:
            error(f"{profile_path} seems to be corrupted, try to login again.")
        else:
            mc_token = profile['mc_token']
            if mc_token.not_after < datetime.now(datetime.UTC):
                refresh(profile)
                with open(profile_path, 'w+') as f:
                    json.dump(profile, f, default=custom_encode)
            return profile

    profile = login_and_get_profile()
    profile_path.parent.mkdir(parents=True, exist_ok=True)
    with open(profile_path, 'w+') as f:
        json.dump(profile, f, default=custom_encode)
        return profile


try:
    profile_path_name = expanduser('~/.local/share/minecraft.nix/profile.json')
    for i in range(len(argv)):
        if argv[i] == '--profile' and i + 1 < len(argv):
            profile_path_name = expanduser(argv[i + 1])
            break
    authenticate(Path(profile_path_name))
    info("Successfully authenticated.")
    exit(0)
except Exception as e:
    error(f"Authentication Failed: {type(e).__name__}: {e}.")
    exit(1)
