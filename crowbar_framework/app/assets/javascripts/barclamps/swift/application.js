/**
 * Copyright 2011-2013, Dell
 * Copyright 2013-2014, SUSE LINUX Products GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

$(document).ready(function($) {
  $('#middlewares_staticweb_enabled, #middlewares_tempurl_enabled, #middlewares_formpost_enabled').on('change', function() {
    var value = $(this).val();

    var delay_auth_decision = $('#keystone_delay_auth_decision')
    var backup_delay_auth_decision = delay_auth_decision.data('backup');

    if (value == 'true') {
      if (backup_delay_auth_decision == undefined) {
        delay_auth_decision.data('backup', delay_auth_decision.val());
      }
      delay_auth_decision.val('true').attr('disabled', 'disabled').trigger('change');
    }
    else if ($('#middlewares_staticweb_enabled').val() == 'false' &&
             $('#middlewares_tempurl_enabled').val() == 'false' &&
             $('#middlewares_formpost_enabled').val() == 'false')
    {
      delay_auth_decision.removeAttr('disabled');
      if (backup_delay_auth_decision != undefined) {
        delay_auth_decision.val(backup_delay_auth_decision).trigger('change');
        delay_auth_decision.removeData('backup');
      }
    }
  }).trigger('change');
});
