--
-- MoneyMoney Web Banking Extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) 2014 Moritz Müller
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--
-- Support for LBS building savings contracts.
--


WebBanking{version     = 1.06,
           country     = "de",
           services    = {"LBS Baden-Württemberg",
                          "LBS Bayern",
                          "LBS Nord",
                          "LBS Ostdeutsche Landesbausparkasse",
                          "LBS Schleswig-Holstein-Hamburg",
                          "LBS Hessen-Thüringen",
                          "LBS West",
                          "LBS Saar"},
           description = string.format(MM.localizeText("Support for %s building savings contracts"), "LBS")}


function SupportsBank (protocol, bankCode)
  if protocol == ProtocolWebBanking then
    if bankCode == "LBS Baden-Württemberg" then
      return "https://kundenservice.lbs.de/bw/guiServlet"
    elseif bankCode == "LBS Bayern" then
      return "https://meine.lbs-bayern.de/"
    elseif bankCode == "LBS Nord" then
      return "https://kunden-service.lbs.de/nord"
    elseif bankCode == "LBS Ostdeutsche Landesbausparkasse" then
      return "https://kunden-service.lbs.de/ost"
    elseif bankCode == "LBS Schleswig-Holstein-Hamburg" then
      return "https://kunden-service.lbs.de/shh"
    elseif bankCode == "LBS Hessen-Thüringen" then
      return "https://kundenservice.lbs.de/ht/guiServlet"
    elseif bankCode == "LBS West" then
      return "https://kundenservice.lbs.de/west/guiServlet"
    elseif bankCode == "LBS Saar" then
      return "https://kunden-service.lbs.de/saarland"
    end
  end
end


local function strToDate (str)
  -- Helper function for converting localized date strings to timestamps.
  local d, m, y = string.match(str, "(%d%d).(%d%d).(%d%d%d%d)")
  return os.time{year=y, month=m, day=d}
end


local function strToAmount (str)
  -- Helper function for converting localized amount strings to Lua numbers.
  str = string.gsub(string.gsub(str, "[^%d,-]", ""), ",", ".")
  return tonumber(str)
end


-- The following variables are used to save state.
local connection
local html


function InitializeSession (protocol, bankCode, username, customer, password)
  -- Create HTTPS connection object.
  connection = Connection()
  connection.language = "de-de"

  -- Fetch login page.
  local url = SupportsBank(protocol, bankCode)
  html = HTML(connection:get(url))

  -- Follow redirect.
  if html:xpath("//title[contains(text(),'Redirect')]"):length() > 0 then
    html = HTML(connection:request(html:xpath("//form"):submit()))
  elseif html:xpath("//input[@name='PROVIDER_ID']"):length() > 0 then
    html = HTML(connection:request(html:xpath("//form"):submit()))
  end

  -- Check for temporary errors.
  local message = html:xpath("//div[contains(@style,'color:red;')]"):text()
  if string.len(message) > 0 then
    print("Response: " .. message)
    return MM.localizeText("The server of your bank responded with an internal error. Please try again later.")
  end

  -- Fill in login credentials.
  html:xpath("//input[@name='IN_ID']"):attr("value", username)
  html:xpath("//input[@name='IN_PIN']"):attr("value", password)

  -- Submit login form.
  html = HTML(connection:request(html:xpath("//input[@type='submit']"):click()))

  -- Check for login errors.
  local message = html:xpath("//div[@class='alertbox']"):text()
  if string.len(message) > 0 then
    print("Response: " .. message)
    return LoginFailed
  end
  local message = html:xpath("//div[@class='technicalError']"):text()
  if string.len(message) > 0 then
    print("Response: " .. message)
    return LoginFailed
  end
  local message = html:xpath("//div[contains(@style,'color:red;')]"):text()
  if string.len(message) > 0 then
    print("Response: " .. message)
    return LoginFailed
  end
end


function ListAccounts (knownAccounts)
  local accounts = {}
  local owner = owner

  html:xpath("//form//tr"):each(function (index, tr)
    if index > 1 then
                local name = html:xpath("//tr[" .. index .. "]/td[6]"):text()
                local accountNumber = html:xpath("//tr[" .. index .. "]/td[2]"):text()
                local balance = html:xpath("//tr[" .. index .. "]/td[4]"):text()

                if string.len(name) > 0 then
                        local account = {
                                name          = name,
                                accountNumber = accountNumber,
                                owner         = owner,
                                currency      = string.sub(balance, -3),
                                type          = AccountTypeSavings
                        }
                        table.insert(accounts, account)
        end
    end
  end)

  return accounts
end


function RefreshAccount (account, since)
  local balance      = nil
  local transactions = nil

  local accountNumberSelected = account.accountNumber

  html:xpath("//form//tr"):each(function (index, tr)
        local accountNumber = html:xpath("//tr[" .. index .. "]/td[2]"):text()

        if accountNumberSelected == accountNumber then
                -- load balance
                balance = strToAmount(html:xpath("//tr[" .. index .. "]/td[4]"):text())

                -- set account
                local name = html:xpath("//tr[" .. index .. "]/td[6]"):text()
                html:xpath("//tr[" .. index .. "]/td[1]/input"):attr("checked", "checked")
                print("selected: " .. name)
        else
                html:xpath("//tr[" .. index .. "]/td[1]/input"):attr("checked", "")
        end
  end)

  -- open transactions
  if html:xpath("//input[@name='REQ_ID.BSVUMS']"):length() > 0 then
    html = HTML(connection:request(html:xpath("//input[@name='REQ_ID.BSVUMS']"):click()))
  else
    html = HTML(connection:request(html:xpath("//input[contains(@name,'Kontoumsaetze')]"):click()))
  end

  transactions = {}
  html:xpath("//table//tr"):each(function (index, tr)

          local bookingDate = html:xpath("(//table//tr)[" .. index .. "]/td[1]"):text()

          if string.match(bookingDate, "%d%d.%d%d.%d%d%d%d") then
                  -- parse through statements

                  local transaction = {}
                  transaction.bookingDate = strToDate(bookingDate)
                  transaction.valueDate = strToDate(html:xpath("(//table//tr)[" .. index .. "]/td[2]"):text())
                  transaction.amount = strToAmount(html:xpath("(//table//tr)[" .. index .. "]/td[3]"):text())
                  transaction.currency = string.sub(html:xpath("(//table//tr)[" .. index .. "]/td[3]"):text(), -3)
                  transaction.purpose = html:xpath("(//table//tr)[" .. index .. "]/td[4]"):text()
                  table.insert (transactions, transaction)
          end
  end)

  if html:xpath("//div[@class='buttonsInLine']//a"):length() > 0 then
    html = HTML(connection:request(html:xpath("//div[@class='buttonsInLine']//a"):click()))
  else
    html = HTML(connection:request(html:xpath("//input[contains(@name,'Kontouebersicht')]"):click()))
  end

  return {balance=balance, transactions=transactions}

end


function EndSession ()
  local a = html:xpath("//a[contains(text(),'Logoff')]")
  if a:length() > 0 then
    connection:request(a:click())
  end
end
