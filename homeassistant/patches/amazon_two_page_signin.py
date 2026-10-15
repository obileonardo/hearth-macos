"""Teach aioamazondevices Amazon's two-page sign-in.

Amazon's sign-in now takes the email on one page and the password on the next.
aioamazondevices 16.3.x posts both to the first page, lands on the password page,
finds no one-time-code box and reports "Invalid authentication". This adds the
missing step: when the password page comes back, submit the password on it.

Check first with the read-only default; use --apply only after approval.
Copy patch_safety.py beside this script. See README.md for preflight, compatibility
limitations and an approved container rollback/restart procedure.

"""

from patch_safety import arguments, commit, replace_once

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

def plan(folder):
    path = folder / "login.py"
    source = path.read_text()
    if marker in source and source.count(anchor + addition) != 1:
        raise ValueError("login.py: partial sign-in patch; nothing applied")
    if diag_marker in source and source.count(diag_anchor + diag_addition) != 1:
        raise ValueError("login.py: partial diagnostics patch; nothing applied")
    updated = replace_once(source, anchor, anchor + addition, "two-page sign-in")
    updated = replace_once(updated, diag_anchor, diag_anchor + diag_addition, "sign-in diagnostics")
    return [(path, source, updated)]


def main():
    args = arguments("Check/apply the optional Amazon two-page sign-in maintenance patch")
    if args.root is None:
        import aioamazondevices
        from pathlib import Path
        args.root = Path(aioamazondevices.__file__).parent
    commit(plan(args.root), args.apply)


if __name__ == "__main__":
    main()
