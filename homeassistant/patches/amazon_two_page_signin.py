"""Teach aioamazondevices Amazon's two-page sign-in.

Amazon's sign-in now takes the email on one page and the password on the next.
aioamazondevices 16.3.x posts both to the first page, lands on the password page,
finds no one-time-code box and reports "Invalid authentication". This adds the
missing step: when the password page comes back, submit the password on it.

Apply inside the Home Assistant container, then restart it:
    docker cp amazon_two_page_signin.py homeassistant:/tmp/ && \\
    docker exec homeassistant python3 /tmp/amazon_two_page_signin.py && docker restart homeassistant
Safe to run twice. Re-run after a Home Assistant image update.
"""

import pathlib

import aioamazondevices

path = pathlib.Path(aioamazondevices.__file__).parent / "login.py"
source = path.read_text()
marker = "# two-page sign-in patch"

anchor = '''        _LOGGER.debug("Register at %s", login_url)
        login_soup, _ = await self._http_wrapper.session_request(
            method=login_method,
            url=login_url,
            input_data=login_inputs,
        )
'''

addition = '''
        ''' + marker + '''
        if login_soup.find("input", id="ap_password") and not login_soup.find(
            "input", id="auth-mfa-otpcode"
        ):
            _LOGGER.debug("Password page found, submitting the password on it")
            login_method, login_url = self._get_request_from_soup(login_soup)
            login_inputs = self._get_inputs_from_soup(login_soup)
            login_inputs["email"] = self._session_state_data.login_email
            login_inputs["password"] = self._session_state_data.login_password
            login_soup, _ = await self._http_wrapper.session_request(
                method=login_method,
                url=login_url,
                input_data=login_inputs,
            )
'''

diag_marker = "# sign-in diagnostics patch"
diag_anchor = '''            _LOGGER.debug(
                'Cannot find "auth-mfa-otpcode" in html source [%s]', login_url
            )
'''
diag_addition = '''            ''' + diag_marker + '''
            try:
                _title = login_soup.title.get_text(" ", strip=True) if login_soup.title else ""
                _alerts = [" ".join(a.get_text(" ").split())[:200] for a in login_soup.select(".a-alert-content, .a-alert-heading, h1, h4")][:6]
                _fields = [(i.get("type"), i.get("name"), i.get("id")) for i in login_soup.find_all("input") if i.get("type") != "hidden"]
                _forms = [(f.get("name"), f.get("id"), f.get("action", "")[:60]) for f in login_soup.find_all("form")]
                _LOGGER.warning("Sign-in stopped on page: title=%r alerts=%r fields=%r forms=%r", _title, _alerts, _fields, _forms)
            except Exception as _err:  # never let diagnostics break sign-in
                _LOGGER.warning("Sign-in diagnostics failed: %s", _err)
'''
if diag_marker not in source and diag_anchor in source:
    source = source.replace(diag_anchor, diag_anchor + diag_addition, 1)
    path.write_text(source)
    print("diagnostics added")

if marker in source:
    print("already patched:", path)
elif anchor not in source:
    raise SystemExit(f"login.py has changed shape, patch not applied: {path}")
else:
    path.write_text(source.replace(anchor, anchor + addition, 1))
    print("patched:", path)
